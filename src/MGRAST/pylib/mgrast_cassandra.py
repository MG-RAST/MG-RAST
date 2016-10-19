
import bisect
import datetime
import cass_connection
from collections import defaultdict
import cassandra.query as cql

M5NR_VERSION = 1

class M5nrHandle(object):
    def __init__(self, hosts, version=M5NR_VERSION):
        keyspace = "m5nr_v"+str(version)
        self.session = cass_connection.create(hosts).connect(keyspace)
        self.session.default_timeout = 300
        self.session.row_factory = cql.dict_factory
    def close(self):
        cass_connection.destroy()
    def get_records_by_id(self, ids, source=None, index=False, iterator=False):
        found = []
        table = "index_annotation" if index else "id_annotation"
        id_str = ",".join(map(str, ids))
        if source:
            query = "SELECT * FROM %s WHERE id IN (%s) AND source='%s'"%(table, id_str, source)
        else:
            query = "SELECT * FROM %s WHERE id IN (%s)"%(table, id_str)
        rows = self.session.execute(query)
        if iterator:
            return rows
        else:
            for r in rows:
                r['is_protein'] = 1 if r['is_protein'] else 0
                found.append(r)
            return found
    def get_records_by_md5(self, md5s, source=None, index=False, iterator=False):
        found = []
        table = "midx_annotation" if index else "md5_annotation"
        md5_str = ",".join(map(lambda x: "'"+x+"'", md5s))
        if source:
            query = "SELECT * FROM %s WHERE md5 IN (%s) AND source='%s'"%(table, md5_str, source)
        else:
            query = "SELECT * FROM %s WHERE md5 IN (%s)"%(table, md5_str)
        rows = self.session.execute(query)
        if iterator:
            return rows
        else:
            for r in rows:
                r['is_protein'] = 1 if r['is_protein'] else 0
                found.append(r)
            return found
    def get_taxa_hierarchy(self):
        found = {}
        query = "SELECT * FROM organisms_ncbi"
        rows  = self.session.execute(query)
        for r in rows:
            found[r['name']] = [r['tax_domain'], r['tax_phylum'], r['tax_class'], r['tax_order'], r['tax_family'], r['tax_genus'], r['tax_species']]
        return found
    def get_ontology_hierarchy(self, source=None):
        found = defaultdict(dict)
        if source:
            prep = self.session.prepare("SELECT * FROM ont_level1 WHERE source = ?")
            rows = self.session.execute(prep, [source])
        else:
            rows = self.session.execute("SELECT * FROM ont_level1")
        for r in rows:
            found[r['source']][r['level1']] = r['name']
        if source:
            return found[source]
        else:
            return found
    def get_org_taxa_map(self, taxa):
        found = {}
        tname = "tax_"+taxa.lower()
        query = "SELECT * FROM "+tname
        rows  = self.session.execute(query)
        for r in rows:
            found[r['name']] = r[tname]
        return found
    def get_ontology_map(self, source, level):
        found = {}
        level = level.lower()
        prep = self.session.prepare("SELECT * FROM ont_%s WHERE source = ?"%level)
        rows = self.session.execute(prep, [source])
        for r in rows:
            found[r['name']] = r[level]
        return found
    def get_organism_by_taxa(self, taxa, match=None):
        # if match is given, return subset that contains match, else all
        found = set()
        tname = "tax_"+taxa.lower()
        query = "SELECT * FROM "+tname
        rows = self.session.execute(query)
        for r in rows:
            if match and (match.lower() in r[tname].lower()):
                found.add(r['name'])
            elif not match:
                found.add(r['name'])
        return list(found)
    def get_ontology_by_level(self, source, level, match=None):
        # if match is given, return subset that contains match, else all
        found = set()
        level = level.lower()
        prep = self.session.prepare("SELECT * FROM ont_%s WHERE source = ?"%level)
        rows = self.session.execute(prep, [source])
        for r in rows:
            if match and (match.lower() in r[level].lower()):
                found.add(r['name'])
            elif not match:
                found.add(r['name'])
        return list(found)

class JobHandle(object):
    def __init__(self, hosts, version=M5NR_VERSION):
        keyspace = "mgrast_abundance"
        self.version = int(version)
        self.session = cass_connection.create(hosts).connect(keyspace)
        self.session.default_timeout = 300
        self.session.row_factory = cql.tuple_factory
    def close(self):
        cass_connection.destroy()
    def last_updated(self, job):
        job  = int(job)
        prep = self.session.prepare("SELECT updated_on FROM job_info WHERE version = ? AND job = ?")
        rows = self.session.execute(prep, [self.version, job])
        if len(rows.current_rows) > 0:
            return rows[0][0]
        else:
            return None
    def get_job_records(self, job, fields, evalue=None, identity=None, alength=None):
        job = int(job)
        query = "SELECT "+",".join(fields)+" from job_md5s WHERE version = ? AND job = ?"
        where = [self.version, job]
        if evalue:
            query += " AND exp_avg <= ?"
            where.append(int(evalue) * -1)
        if identity:
            query += " AND ident_avg >= ?"
            where.append(int(identity))
        if alength:
            query += " AND len_avg >= ?"
            where.append(int(alength))
        prep = self.session.prepare(query)
        return self.session.execute(prep, where)
    def get_md5_record(self, job, md5):
        # get index for one md5
        job = int(job)
        query = "SELECT seek, length FROM job_md5s WHERE version = %d AND job = %d AND md5 = %s"%(self.version, job, md5)
        rows  = self.session.execute(query)
        if (len(rows.current_rows) > 0) and (rows[0][1] > 0):
            return [ rows[0][0], rows[0][1] ]
        else:
            return None
    def get_md5_records(self, job, md5s=None, evalue=None, identity=None, alength=None):
        # get indexes for given md5 list or cutoff values
        job = int(job)
        found = []
        query = "SELECT seek, length FROM job_md5s WHERE version = %d AND job = %d"%(self.version, job)
        if md5s and (len(md5s) > 0):
            query += " AND md5 IN (" + ",".join(map(lambda x: "'"+x+"'", md5s)) + ")"
        else:
            if evalue:
                query += " AND exp_avg <= %d"%(int(evalue) * -1)
            if identity:
                query += " AND ident_avg >= %d"%(int(identity))
            if alength:
                query += " AND len_avg >= %d"%(int(alength))
        rows = self.session.execute(query)
        for r in rows:
            if r[1] == 0:
                continue
            pos = bisect.bisect(found, (r[0], None))
            if (pos > 0) and ((found[pos-1][0] + found[pos-1][1]) == r[0]):
                found[pos-1][1] = found[pos-1][1] + r[1]
            else:
                bisect.insort(found, (r[0], r[1]))
        return found
    def get_row_count(self, job, table, maxRow=None):
        job = int(job)
        query = "SELECT count(*) FROM job_%ss WHERE version = %d AND job = %d"%(table, self.version, job)
        if maxRow:
            query += " LIMIT %d"%int(maxRow)
        rows = self.session.execute(query)
        if len(rows.current_rows) > 0:
            return rows[0][0]
        else:
            return 0
    def has_job(self, job):
        job = int(job)
        query = "SELECT * FROM job_info WHERE version = %d AND job = %d"%(self.version, job)
        rows  = self.session.execute(query)
        if len(rows.current_rows) > 0:
            return 1
        else:
            return 0
    def is_loaded(self, job):
        job = int(job)
        query = "SELECT loaded FROM job_info WHERE version = %d AND job = %d"%(self.version, job)
        rows  = self.session.execute(query)
        if (len(rows.current_rows) > 0) and rows[0][0]:
            return 1
        else:
            return 0
    def set_loaded(self, job, loaded):
        job = int(job)
        value = True if loaded else False
        prep  = self.session.prepare("UPDATE job_info SET loaded = ?, updated_on = ? WHERE version = ? AND job = ?")
        self.session.execute(prep, [value, datetime.datetime.now(), self.version, job])
    def delete_job(self, job):
        job = int(job)
        batch = cql.BatchStatement()
        if self.has_job(job):
            # if job exists, set unloaded
            batch.add(cql.SimpleStatement("UPDATE job_info SET loaded = false WHERE version = %d AND job = %d"), (self.version, job))
        batch.add(cql.SimpleStatement("DELETE FROM job_md5s WHERE version = %d AND job = %d"), (self.version, job))
        batch.add(cql.SimpleStatement("DELETE FROM job_lcas WHERE version = %d AND job = %d"), (self.version, job))
        self.session.execute(batch)
    def update_job_info(self, job, md5s, loaded):
        job = int(job)
        value  = True if loaded else False
        insert = "UPDATE job_info SET md5s = ?, updated_on = ?, loaded = ? WHERE version = ? AND job = ?"
        prep   = self.session.prepare(insert)
        self.session.execute(prep, [md5s, datetime.datetime.now(), value, self.version, job])
    def insert_job_info(self, job, md5s, loaded):
        job = int(job)
        value  = True if loaded else False
        insert = "INSERT INTO job_info (version, job, md5s, updated_on, loaded) VALUES (?, ?, ?, ?, ?)"
        prep   = self.session.prepare(insert)
        self.session.execute(prep, [self.version, job, md5s, datetime.datetime.now(), value])
    def insert_job_md5s(self, job, rows):
        job = int(job)
        insert = "INSERT INTO job_md5s (version, job, md5, abundance, exp_avg, ident_avg, len_avg, seek, length) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        prep   = self.session.prepare(insert)
        batch  = cql.BatchStatement(consistency_level=cql.ConsistencyLevel.QUORUM)
        for (md5, abundance, exp_avg, ident_avg, len_avg, seek, length) in rows:
            if not seek:
                seek = 0
            if not length:
                length = 0
            batch.add(prep, (self.version, job, md5, abundance, exp_avg, ident_avg, len_avg, seek, length))
        self.session.execute(batch)
    def insert_job_lcas(self, job, rows):
        job = int(job)
        insert = "INSERT INTO job_lcas (version, job, lca, abundance, exp_avg, ident_avg, len_avg, md5s, level) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        prep   = self.session.prepare(insert)
        batch  = cql.BatchStatement(consistency_level=cql.ConsistencyLevel.QUORUM)
        for (lca, abundance, exp_avg, ident_avg, len_avg, md5s, level) in rows:
            batch.add(prep, (self.version, job, lca, abundance, exp_avg, ident_avg, len_avg, md5s, level))
        self.session.execute(batch)
    

