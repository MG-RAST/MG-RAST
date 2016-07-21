#!/usr/bin/env python

import sys
import time
import random
import psycopg2
import requests
from optparse import OptionParser
from cassandra.cluster import Cluster
from cassandra.policies import RetryPolicy

MAX_INT = 24468843

def random_array(size):
    array = []
    for i in range(size):
        array.append(random.randint(1, MAX_INT))
    return array

def main(args):
    parser = OptionParser()
    parser.add_option("", "--batch", dest="batch", type="int", default=100, help="query batch size, default: 100")
    parser.add_option("", "--count", dest="count", type="int", default=10, help="number of query iterations, default: 10")
    parser.add_option("", "--phost", dest="phost", default=None, help="Postgres host")
    parser.add_option("", "--pname", dest="pname", default=None, help="Postgres name")
    parser.add_option("", "--puser", dest="puser", default=None, help="Postgres user")
    parser.add_option("", "--chost", dest="chost", default=None, help="Cassandra host")
    parser.add_option("", "--cname", dest="cname", default=None, help="Cassandra name")
    parser.add_option("", "--shost", dest="shost", default=None, help="SOLR host")
    parser.add_option("", "--sname", dest="sname", default=None, help="SOLR collection")
    (opts, args) = parser.parse_args()
    
    handle = None
    mode = ""
    
    # test PSQL
    if opts.phost and opts.pname and opts.puser:
        mode = "sql"
        handle = psycopg2.connect(
            host=opts.phost,
            database=opts.pname,
            user=opts.puser
        )
    # test CASS
    elif opts.chost and opts.cname:
        mode = "cql"
        handle = Cluster(
            contact_points=[opts.chost],
            default_retry_policy = RetryPolicy()
        )
    # test solr
    elif opts.shost and opts.sname:
        mode = "solr"
        surl = "http://"+opts.shost+"/solr/"+opts.sname+"/select"
        shead = {'Content-Type': 'application/x-www-form-urlencoded'}
        sfields = "%2C".join(['md5_id', 'source', 'md5', 'accession', 'function', 'organism'])
    else:
        parser.error("Invalid usage")
    
    start = time.time()
    found = set()
    for i in range(opts.count):
        ints = random_array(opts.batch)
        query = "SELECT * FROM md5_id_annotation WHERE id IN ("+",".join(map(str, ints))+");"
        if mode == "sql":
            cursor = handle.cursor()
            cursor.execute(query)
            data = cursor.fetchone()
            while (data):
                found.add(data[2])
                data = cursor.fetchone()
        elif mode == "cql":
            session = handle.connect(opts.cname)
            rows = session.execute(query)
            for r in rows:
                found.add(r.md5)
        elif mode == "solr":
            query = "md5_id:("+" OR ".join(map(str, ints))+")"
            sdata = "q=*%3A*&fq="+query+"&start=0&rows=1000000000&wt=json&fl="+sfields
            req = requests.post(surl, headers=shead, data=sdata, allow_redirects=True)
            rj = req.json()
            for d in rj['response']['docs']:
                found.add(d['md5'])
    
    end = time.time()
    print "%d loops of size %d ran in %d seconds"%(opts.count, opts.batch, int(round(end-start)))
    print "%d ids requested, %d md5s found"%((opts.count * opts.batch), len(found))
    

if __name__ == "__main__":
    sys.exit( main(sys.argv) )

