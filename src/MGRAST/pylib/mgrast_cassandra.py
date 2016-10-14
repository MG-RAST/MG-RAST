import bisect
import datetime
from collections import defaultdict
from cassandra.cluster import Cluster
from cassandra.policies import RetryPolicy
from cassandra.query import dict_factory, BatchStatement, SimpleStatement

M5NR_VERSION = 1
CASS_CLUSTER = None

def set_cluster(hosts):
    if CASS_CLUSTER is None:
        CASS_CLUSTER = Cluster(contact_points = hosts, default_retry_policy = RetryPolicy())

def close_cluster():
    CASS_CLUSTER.shutdown()
    CASS_CLUSTER = None

def test_connection(hosts, db):
    try:
        rows = ()
        cluster = Cluster(contact_points = hosts, default_retry_policy = RetryPolicy())
        if db == "job":
            session = cluster.connect("mgrast_abundance")
            rows = self.session.execute("SELECT * FROM mgrast_abundance limit 5")
        elif db == "m5nr":
            session = cluster.connect("m5nr_v"+str(M5NR_VERSION))
            rows = self.session.execute("SELECT * FROM md5_annotation limit 5")
        cluster.shutdown()
        if len(rows) > 0:
            return True
        else:
            return False
    except:
        return False

class M5nrHandle(object):
    def __init__(self, hosts, version=M5NR_VERSION):
        set_cluster(hosts)
        keyspace = "m5nr_v"+str(version)
        self.session = CASS_CLUSTER.connect(keyspace)
        self.session.default_timeout = 300
        self.session.row_factory = dict_factory
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
        rows = self.session.execute(query)
        for r in rows:
            found[r['name']] = [r['tax_domain'], r['tax_phylum'], r['tax_class'], r['tax_order'], r['tax_family'], r['tax_genus'], r['tax_species']]
        return found
    def get_ontology_hierarchy(self, source=None):
        found = defaultdict(dict)
        if source is None:
            rows = self.session.execute("SELECT * FROM ont_level1")
        else:
            prep = self.session.prepare("SELECT * FROM ont_level1 WHERE source = ?")
            rows = self.session.execute(prep, [source])
        for r in rows:
            found[r['source']][r['level1']] = r['name']
        if source is None:
            return found
        else:
            return found[source]
    def get_org_taxa_map(self, taxa):
        found = {}
        tname = "tax_"+taxa.lower()
        query = "SELECT * FROM "+tname
        rows = self.session.execute(query)
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
            elif match is None:
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
            elif match is None:
                found.add(r['name'])
        return list(found)

class JobHandle(object):
    def __init__(self, hosts, version=M5NR_VERSION):
        set_cluster(hosts)
        keyspace = "mgrast_abundance"
        self.version = version
        self.session = CASS_CLUSTER.connect(keyspace)
        self.session.default_timeout = 300
        self.session.row_factory = tuple_factory
    def last_updated(self, job):
        prep = self.session.prepare("SELECT updated_on FROM job_info WHERE version = ? AND job = ?")
        rows = self.session.execute(prep, [self.version, job])
        if len(rows) > 0:
            return rows[0]
        else:
            return None
    def get_job_records(self, job, fields, md5s=None, evalue=None, identity=None, alength=None):
        query = "SELECT "+",".join(fields)+" from job_md5s WHERE version = ? AND job = ?"
        where = [self.version, job]
        if md5s and (len(md5s) == 1):
            query += " AND md5 = ?"
            where.append(md5s[0])
        elif md5s and (len(md5s) > 1):
            query += " AND md5 IN ?"
            where.append(md5s)
        if evalue not None:
            query += " AND exp_avg <= ?"
            where.append(evalue)
        if identity not None:
            query += " AND ident_avg >= ?"
            where.append(identity)
        if alength not None:
            query += " AND len_avg >= ?"
            where.append(alength)
        prep = self.session.prepare(query)
        return self.session.execute(prep, where)
    def get_md5_record(self, job, md5):
        query = "SELECT seek, length FROM job_md5s WHERE version = %d AND job = %d AND md5 = %s"%(self.version, job, md5)
        rows = self.session.execute(query)
        if (len(rows) > 0) and (rows[0][1] > 0):
            return [ rows[0][0], rows[0][1] ]
        else:
            return None
    def get_md5_records(self, job, md5s):
        found = []
        md5_str = ",".join(map(lambda x: "'"+x+"'", md5s))
        query = "SELECT seek, length FROM job_md5s WHERE version = %d AND job = %d AND md5 IN (%s)"%(self.version, job, md5_str)
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
    def has_job(self, job):
        prep = self.session.prepare("SELECT * FROM job_info WHERE version = ? AND job = ?")
        rows = self.session.execute(prep, [self.version, job])
        if len(rows) > 0:
            return 1
        else:
            return 0
    def is_loaded(self, job):
        prep = self.session.prepare("SELECT loaded FROM job_info WHERE version = ? AND job = ?")
        rows = self.session.execute(prep, [self.version, job])
        if (len(rows) > 0) and rows[0][0]:
            return 1
        else:
            return 0
    def set_loaded(self, job, loaded):
        value = 'true' if loaded else 'false'
        self.session.execute("UPDATE job_info SET loaded = %s WHERE version = %d AND job = %d")%(value, self.version, job))
    def delete_job(self, job):
        batch = BatchStatement()
        if self.has_job(job):
            # if job exists, set unloaded
            batch.add(SimpleStatement("UPDATE job_info SET loaded = false WHERE version = %d AND job = %d"), (self.version, job))
        batch.add(SimpleStatement("DELETE FROM job_md5s WHERE version = %d AND job = %d"), (self.version, job))
        batch.add(SimpleStatement("DELETE FROM job_lcas WHERE version = %d AND job = %d"), (self.version, job))
        session.execute(batch)
    def insert_job_info(self, job, md5s):
        # always add new job in unloaded state
        insert = "INSERT INTO job_info (version, job, md5s, updated_on, loaded) VALUES (?, ?, ?, ?, ?)"
        prep = self.session.prepare(insert)
        self.ssession.execute(prep, [self.version, job, md5s, datetime.datetime.now(), False])
    def insert_job_md5s(self, job, rows):
        insert = "INSERT INTO job_md5s (version, job, md5, abundance, exp_avg, ident_avg, len_avg, seek, length) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        prep  = self.session.prepare(insert)
        batch = BatchStatement(consistency_level=ConsistencyLevel.QUORUM)
        for (md5, abundance, exp_avg, ident_avg, len_avg, seek, length) in rows:
            batch.add(prep, (self.version, job, md5, abundance, exp_avg, ident_avg, len_avg, seek, length))
        self.ssession.execute(batch)
    def insert_job_lca(self, job, rows):
        insert = "INSERT INTO job_lcas (version, job, lca, abundance, exp_avg, ident_avg, len_avg, md5s, level) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        prep  = self.session.prepare(insert)
        batch = BatchStatement(consistency_level=ConsistencyLevel.QUORUM)
        for (lca, abundance, exp_avg, ident_avg, len_avg, md5s, level) in rows:
            batch.add(prep, (self.version, job, lca, abundance, exp_avg, ident_avg, len_avg, md5s, level))
        self.session.execute(batch)
    

