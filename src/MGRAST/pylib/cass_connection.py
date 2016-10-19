
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

def test(hosts, db):
    try:
        rows = ()
        cluster = Cluster(contact_points = hosts, default_retry_policy = RetryPolicy())
        if db == "job":
            session = cluster.connect("mgrast_abundance")
            rows = self.session.execute("SELECT * FROM mgrast_abundance limit 5")
        elif db == "m5nr":
            session = cluster.connect("m5nr_v1")
            rows = self.session.execute("SELECT * FROM md5_annotation limit 5")
        cluster.shutdown()
        if len(rows) > 0:
            return 1
        else:
            return 0
    except:
        return 0
