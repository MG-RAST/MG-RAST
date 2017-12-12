
import os
import json
import bisect
import datetime
import cass_connection
from collections import defaultdict
import cassandra.query as cql

M5NR_VERSION = 1

def rmqLogger(channel, stype, statement, bulk=0):
    if not channel:
        return
    truncate = (statement[:98] + '..') if len(statement) > 100 else statement
    body = {
        'timestamp': datetime.datetime.now().isoformat(),
        'type':      stype,
        'statement': truncate,
        'bulk':      bulk
    }
    if 'HOSTNAME' in os.environ:
        body['host'] = os.environ['HOSTNAME']
    try:
        channel.basic_publish(
            exchange='',
            routing_key=cass_connection.RM_QUEUE,
            body=json.dumps(body),
            properties=cass_connection.RMQ_PROP
        )
    except:
        # silently ignore broken logging
        pass

class M5nrHandle(object):
    def __init__(self, hosts, version=M5NR_VERSION):
        keyspace = "m5nr_v"+str(version)
        self.session = cass_connection.create(hosts).connect(keyspace)
        self.session.default_timeout = 300
        self.session.row_factory = cql.dict_factory
        self.channel = None
        try:
            self.channel = cass_connection.rmqConnection().channel()
        except:
            pass
    def close(self):
        cass_connection.destroy()
    ### retrieve M5NR records
    def get_records_by_id(self, ids, source=None, index=False, iterator=False):
        found = []
        table = "index_annotation" if index else "id_annotation"
        id_str = ",".join(map(str, ids))
        if source:
            query = "SELECT * FROM %s WHERE id IN (%s) AND source='%s'"%(table, id_str, source)
        else:
            query = "SELECT * FROM %s WHERE id IN (%s)"%(table, id_str)
        rmqLogger(self.channel, 'select', query)
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
        rmqLogger(self.channel, 'select', query)
        rows = self.session.execute(query)
        if iterator:
            return rows
        else:
            for r in rows:
                r['is_protein'] = 1 if r['is_protein'] else 0
                found.append(r)
            return found
    def get_functions_by_id(self, ids, compress, iterator=False):
        id_str = ",".join(map(str, ids))
        query = "SELECT * FROM functions WHERE id IN (%s)"%(id_str)
        rmqLogger(self.channel, 'select', query)
        rows = self.session.execute(query)
        if iterator:
            return rows
        else:
            if compress == 1:
                found = {}
                for r in rows:
                    found[ r['id'] ] = r['name']
            else:
                found = []
                for r in rows:
                    found.append( {'function_id': r['id'], 'function': r['name']} )
            return found
    ### retrieve full hierarchies
    def get_taxa_hierarchy(self):
        found = {}
        query = "SELECT * FROM organisms_ncbi"
        rmqLogger(self.channel, 'select', query)
        rows  = self.session.execute(query)
        for r in rows:
            found[r['name']] = [r['tax_domain'], r['tax_phylum'], r['tax_class'], r['tax_order'], r['tax_family'], r['tax_genus'], r['tax_species']]
        return found
    def get_ontology_hierarchy(self, source=None):
        found = {}
        query = "SELECT * FROM ontologies"
        if source:
            query += " WHERE source = ?"
            prep = self.session.prepare(query)
            for r in self.session.execute(prep, [source]):
                found[r['name']] = [r['level1'], r['level2'], r['level3'], r['level4']]
        else:
            for r in self.session.execute(query):
                if r['source'] not in found:
                    found[r['source']] = {}
                found[r['source']][r['name']] = [r['level1'], r['level2'], r['level3'], r['level4']]
        rmqLogger(self.channel, 'select', query)
        return found
    ### retrieve hierarchy mapping: leaf -> level
    def get_org_taxa_map(self, taxa):
        found = {}
        tname = "tax_"+taxa.lower()
        query = "SELECT * FROM "+tname
        rmqLogger(self.channel, 'select', query)
        rows  = self.session.execute(query)
        for r in rows:
            found[r['name']] = r[tname]
        return found
    def get_ontology_map(self, level, source=None):
        found = {}
        level = level.lower()
        query = "SELECT * FROM ont_%s"%level
        if source:
            query += " WHERE source = ?"
            prep = self.session.prepare(query)
            for r in self.session.execute(prep, [source]):
                found[r['name']] = r[level]
        else:
            for r in self.session.execute(query):
                if r['source'] not in found:
                    found[r['source']] = {}
                found[r['source']][r['name']] = r[level]
        rmqLogger(self.channel, 'select', query)
        return found
    ### retrieve hierarchy: leaf list for a level
    def get_organism_by_taxa(self, taxa, match=None):
        # if match is given, return subset that contains match, else all
        found = set()
        tname = "tax_"+taxa.lower()
        query = "SELECT * FROM "+tname
        rmqLogger(self.channel, 'select', query)
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
        query = "SELECT * FROM ont_%s WHERE source = ?"%level
        rmqLogger(self.channel, 'select', query)
        prep = self.session.prepare(query)
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
        self.channel = None
        try:
            self.channel = cass_connection.rmqConnection().channel()
        except:
            pass
    def close(self):
        cass_connection.destroy()
    ## get iterator for md5 records of a job
    def get_job_records(self, job, fields, swap=None, evalue=None, identity=None, alength=None):
        job = int(job)
        if swap:
            identity, alength = alength, identity
        query = "SELECT "+",".join(fields)+" FROM job_md5s WHERE version = ? AND job = ?"
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
        if evalue or identity or alength:
            query += " ALLOW FILTERING"
        rmqLogger(self.channel, 'select', query)
        prep = self.session.prepare(query)
        return self.session.execute(prep, where)
    ## get iterator for lca records of a job
    def get_lca_records(self, job, fields, swap=None, evalue=None, identity=None, alength=None):
        job = int(job)
        if swap:
            identity, alength = alength, identity
        query = "SELECT "+",".join(fields)+" FROM job_lcas WHERE version = ? AND job = ?"
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
        if evalue or identity or alength:
            query += " ALLOW FILTERING"
        rmqLogger(self.channel, 'select', query)
        prep = self.session.prepare(query)
        return self.session.execute(prep, where)
    ## get index for one md5
    def get_md5_record(self, job, md5):
        job = int(job)
        query = "SELECT seek, length FROM job_md5s WHERE version = ? AND job = ? AND md5 = ?"
        rmqLogger(self.channel, 'select', query)
        prep = self.session.prepare(query)
        rows = self.session.execute(prep, [self.version, job, md5])
        if (len(rows.current_rows) > 0) and (rows[0][1] > 0):
            return [ rows[0][0], rows[0][1] ]
        else:
            return None
    ## get indexes for given md5 list or cutoff values
    def get_md5_records(self, job, swap=None, md5s=None, evalue=None, identity=None, alength=None):
        job = int(job)
        if swap:
            identity, alength = alength, identity
        found = []
        query = "SELECT seek, length FROM job_md5s WHERE version = %d AND job = %d"%(self.version, job)
        if md5s and (len(md5s) > 0):
            query += " AND md5 IN (" + ",".join(map(lambda x: "'"+x+"'", md5s)) + ")"
        elif evalue or identity or alength:
            if evalue:
                query += " AND exp_avg <= %d"%(int(evalue) * -1)
            if identity:
                query += " AND ident_avg >= %d"%(int(identity))
            if alength:
                query += " AND len_avg >= %d"%(int(alength))
            query += " ALLOW FILTERING"
        rmqLogger(self.channel, 'select', query)
        rows = self.session.execute(query)
        for r in rows:
            if r[1] == 0:
                continue
            pos = bisect.bisect(found, (r[0], None))
            if (pos > 0) and ((found[pos-1][0] + found[pos-1][1]) == r[0]):
                found[pos-1] = (found[pos-1][0], found[pos-1][1] + r[1])
            else:
                bisect.insort(found, (r[0], r[1]))
        return found
    ## row counts based on info table counter
    def get_info_count(self, job, val):
        job = int(job)
        query = "SELECT %ss FROM job_info WHERE version = %d AND job = %d"%(val, self.version, job)
        rmqLogger(self.channel, 'select', query)
        rows = self.session.execute(query)
        if len(rows.current_rows) > 0:
            return rows[0][0]
        else:
            return 0
    ## row counts based on data tables
    def get_data_count(self, job, val):
        job = int(job)
        query = "SELECT COUNT(*) FROM job_%ss WHERE version = %d AND job = %d"%(val, self.version, job)
        rmqLogger(self.channel, 'select', query)
        rows = self.session.execute(query)
        if len(rows.current_rows) > 0:
            return rows[0][0]
        else:
            return 0
    ## does job exist
    def has_job(self, job):
        job = int(job)
        query = "SELECT * FROM job_info WHERE version = %d AND job = %d"%(self.version, job)
        rmqLogger(self.channel, 'select', query)
        rows = self.session.execute(query)
        if len(rows.current_rows) > 0:
            return 1
        else:
            return 0
    ## job status
    def last_updated(self, job):
        job = int(job)
        query = "SELECT updated_on FROM job_info WHERE version = %d AND job = %d"%(self.version, job)
        rmqLogger(self.channel, 'select', query)
        rows = self.session.execute(query)
        if len(rows.current_rows) > 0:
            return rows[0][0]
        else:
            return None
    def is_loaded(self, job):
        job = int(job)
        query = "SELECT loaded FROM job_info WHERE version = %d AND job = %d"%(self.version, job)
        rmqLogger(self.channel, 'select', query)
        rows = self.session.execute(query)
        if (len(rows.current_rows) > 0) and rows[0][0]:
            return 1
        else:
            return 0
    ## get all info
    def get_job_info(self, job):
        job = int(job)
        query = "SELECT md5s, lcas, loaded, updated_on FROM job_info WHERE version = %d AND job = %d"%(self.version, job)
        rmqLogger(self.channel, 'select', query)
        rows = self.session.execute(query)
        if len(rows.current_rows) > 0:
            load = 'true' if rows[0][2] else 'false'
            return dict(md5s=rows[0][0], lcas=rows[0][1], loaded=load, updated_on=rows[0][3])
        else:
            return None
    ## update job_info table
    def set_loaded(self, job, loaded):
        job = int(job)
        value = True if loaded else False
        cmd = "UPDATE job_info SET loaded = ?, updated_on = ? WHERE version = ? AND job = ?"
        rmqLogger(self.channel, 'update', cmd)
        update = cql.BoundStatement(
            self.session.prepare(cmd),
            consistency_level=cql.ConsistencyLevel.QUORUM
        ).bind([value, datetime.datetime.now(), self.version, job])
        self.session.execute(update)
    def update_info_md5s(self, job, md5s, loaded):
        job = int(job)
        value = True if loaded else False
        cmd = "UPDATE job_info SET md5s = ?, loaded = ?, updated_on = ? WHERE version = ? AND job = ?"
        rmqLogger(self.channel, 'update', cmd)
        update = cql.BoundStatement(
            self.session.prepare(cmd),
            consistency_level=cql.ConsistencyLevel.QUORUM
        ).bind([int(md5s), value, datetime.datetime.now(), self.version, job])
        self.session.execute(update)
    def update_info_lcas(self, job, lcas, loaded):
        job = int(job)
        value = True if loaded else False
        cmd = "UPDATE job_info SET lcas = ?, loaded = ?, updated_on = ? WHERE version = ? AND job = ?"
        rmqLogger(self.channel, 'update', cmd)
        update = cql.BoundStatement(
            self.session.prepare(cmd),
            consistency_level=cql.ConsistencyLevel.QUORUM
        ).bind([int(lcas), value, datetime.datetime.now(), self.version, job])
        self.session.execute(update)
    def insert_job_info(self, job):
        job = int(job)
        cmd = "INSERT INTO job_info (version, job, md5s, lcas, updated_on, loaded) VALUES (?, ?, ?, ?, ?, ?)"
        rmqLogger(self.channel, 'insert', cmd)
        insert = cql.BoundStatement(
            self.session.prepare(cmd),
            consistency_level=cql.ConsistencyLevel.QUORUM
        ).bind([self.version, job, 0, 0, datetime.datetime.now(), False])
        self.session.execute(insert)
    ## add rows to job data tables, return current total loaded
    def insert_job_md5s(self, job, rows):
        job = int(job)
        cmd = "INSERT INTO job_md5s (version, job, md5, abundance, exp_avg, ident_avg, len_avg, seek, length) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        rmqLogger(self.channel, 'insert', cmd, len(rows))
        insert = self.session.prepare(cmd)
        batch  = cql.BatchStatement(consistency_level=cql.ConsistencyLevel.QUORUM)
        for (md5, abundance, exp_avg, ident_avg, len_avg, seek, length) in rows:
            if not seek:
                seek = 0
            if not length:
                length = 0
            batch.add(insert, (self.version, job, md5, int(abundance), float(exp_avg), float(ident_avg), float(len_avg), int(seek), int(length)))
        # update job_info
        loaded = self.get_info_count(job, 'md5') + len(rows)
        cmd = "UPDATE job_info SET md5s = ?, loaded = ?, updated_on = ? WHERE version = ? AND job = ?"
        rmqLogger(self.channel, 'update', cmd)
        update = self.session.prepare(cmd)
        batch.add(update, (loaded, False, datetime.datetime.now(), self.version, job))
        # execute atomic batch
        self.session.execute(batch)
        return loaded
    def insert_job_lcas(self, job, rows):
        job = int(job)
        cmd = "INSERT INTO job_lcas (version, job, lca, abundance, exp_avg, ident_avg, len_avg, md5s, level) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        rmqLogger(self.channel, 'insert', cmd, len(rows))
        insert = self.session.prepare(cmd)
        batch  = cql.BatchStatement(consistency_level=cql.ConsistencyLevel.QUORUM)
        for (lca, abundance, exp_avg, ident_avg, len_avg, md5s, level) in rows:
            batch.add(insert, (self.version, job, lca, int(abundance), float(exp_avg), float(ident_avg), float(len_avg), int(md5s), int(level)))
        # update job_info
        loaded = self.get_info_count(job, 'lca') + len(rows)
        cmd = "UPDATE job_info SET lcas = ?, loaded = ?, updated_on = ? WHERE version = ? AND job = ?"
        rmqLogger(self.channel, 'update', cmd)
        update = self.session.prepare(cmd)
        batch.add(update, (loaded, False, datetime.datetime.now(), self.version, job))
        # execute atomic batch
        self.session.execute(batch)
        return loaded
    ## delete all job data
    def delete_job(self, job):
        job = int(job)
        batch = cql.BatchStatement(consistency_level=cql.ConsistencyLevel.QUORUM)
        idel = "DELETE FROM job_info WHERE version = %d AND job = %d"%(self.version, job)
        rmqLogger(self.channel, 'delete', idel)
        batch.add(cql.SimpleStatement(idel))
        mdel = "DELETE FROM job_md5s WHERE version = %d AND job = %d"%(self.version, job)
        rmqLogger(self.channel, 'delete', mdel)
        batch.add(cql.SimpleStatement(mdel))
        ldel = "DELETE FROM job_lcas WHERE version = %d AND job = %d"%(self.version, job)
        rmqLogger(self.channel, 'delete', ldel)
        batch.add(cql.SimpleStatement(ldel))
        self.session.execute(batch)

