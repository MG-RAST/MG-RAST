
import pika
from cassandra.cluster import Cluster
from cassandra.policies import RetryPolicy

CASS_CLUSTER = None
RMQ_CONN = None
RMQ_HOST = 'bio-worker20.mcs.anl.gov'
RM_QUEUE = 'cassandra_queries'
RMQ_CRED = pika.PlainCredentials('mgrast', 'nepotism')
RMQ_PROP = pika.BasicProperties(delivery_mode = 2)

def create(hosts):
    global CASS_CLUSTER
    if not CASS_CLUSTER:
        CASS_CLUSTER = Cluster(contact_points = hosts, default_retry_policy = RetryPolicy())
    return CASS_CLUSTER

def destroy():
    global CASS_CLUSTER
    global RMQ_CONN
    if CASS_CLUSTER:
        CASS_CLUSTER.shutdown()
    CASS_CLUSTER = None
    if RMQ_CONN:
        RMQ_CONN.close()
    RMQ_CONN = None

def rmqConnection():
    global RMQ_CONN
    if not RMQ_CONN:
        RMQ_CONN = pika.BlockingConnection(pika.ConnectionParameters(host=RMQ_HOST, credentials=RMQ_CRED))
    return RMQ_CONN

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
            elif self.db == "m5nr":
                session = cluster.connect("m5nr_v1")
            if session:
                status = 1
            cluster.shutdown()
            return status
        except Exception as e: 
            print(e)
            return 0
