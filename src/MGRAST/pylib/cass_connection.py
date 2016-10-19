
from cassandra.cluster import Cluster
from cassandra.policies import RetryPolicy

CASS_CLUSTER = None

def create(hosts):
    global CASS_CLUSTER
    if not CASS_CLUSTER:
        CASS_CLUSTER = Cluster(contact_points = hosts, default_retry_policy = RetryPolicy())
    return CASS_CLUSTER

def destroy():
    global CASS_CLUSTER
    if CASS_CLUSTER:
        CASS_CLUSTER.shutdown()
    CASS_CLUSTER = None

class CassTest(object):
    def __init__(self, hosts, db):
        self.hosts = hosts
        self.db = db
    def test(self):
        try:
            status = 0
            cluster = Cluster(contact_points = self.hosts, default_retry_policy = RetryPolicy())
            if self.db == "job":
                session = cluster.connect("mgrast_abundance")
                rows = session.execute("SELECT * FROM job_md5s limit 5")
            elif self.db == "m5nr":
                session = cluster.connect("m5nr_v1")
                rows = session.execute("SELECT * FROM md5_annotation limit 5")
            cluster.shutdown()
            for r in rows:
                status += 1
            return statu
        except:
            return 0
