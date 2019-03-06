
import re
import time
import json
import shock
import mgrast_cassandra
from collections import defaultdict

UPDATE_SECS  = 300
M5NR_VERSION = 1
CHUNK_SIZE   = 100
SKIP_RE = re.compile('other|unknown|unclassified')

class Abundance(object):
    def __init__(self, hosts, version=M5NR_VERSION, chunk=CHUNK_SIZE):
        self.m5nr = mgrast_cassandra.M5nrHandle(hosts, version)
        self.jobs = mgrast_cassandra.JobHandle(hosts, version)
        self.chunk = int(chunk)
        self.shock = None
    
    def set_shock(self, token=None, bearer='mgrast', url='http://shock.mg-rast.org'):
        self.shock = shock.ShockClient(shock_url=url, bearer=bearer, token=token)
    
    def close(self):
        self.m5nr.close()
        self.jobs.close()
    
    def all_md5s(self, job):
        job = int(job)
        md5s = []
        rows = self.jobs.get_job_records(job, ['md5'])
        for r in rows:
            md5s.append(r[0])
        return md5s
    
    def all_annotation_abundances(self, job, taxa=[], org=0, fun=0, ont=0, node=None):
        job = int(job)
        class local:
            tax = ""
            found   = 0
            tax_map = {}
            org_map = {}                 # tax_lvl : taxa : abundance
            fun_map = defaultdict(int)   # func : abundance
            ont_map = {}                 # source : level1 : abundance
            ont_cat = {}                 # source : ontID : level1
        
        if org and (len(taxa) == 1):
            local.tax = taxa[0]
            # org : taxa
            local.tax_map = self.m5nr.get_org_taxa_map(local.tax)
            local.org_map[taxa[0]] = defaultdict(int)
        elif org and (len(taxa) > 1):
            # org : [ taxa ]
            local.tax_map = self.m5nr.get_taxa_hierarchy()
            for t in taxa:
                local.org_map[t] = defaultdict(int)
        if ont:
            local.ont_cat = self.m5nr.get_ontology_map("level1")
        
        def add_annotations(md5s):
            records = self.m5nr.get_records_by_md5(md5s.keys(), iterator=True)
            for rec in records:
                local.found += 1
                if fun and rec['function']:
                    for f in rec['function']:
                        local.fun_map[f] += md5s[rec['md5']]
                if ont and (rec['source'] in local.ont_cat) and rec['accession']:
                    if rec['source'] not in local.ont_map:
                        local.ont_map[rec['source']] = defaultdict(int)
                    for a in rec['accession']:
                        if a in local.ont_cat[rec['source']]:
                            level = local.ont_cat[rec['source']][a]
                            local.ont_map[rec['source']][level] += md5s[rec['md5']]
                if org and rec['organism']:
                    for o in rec['organism']:
                        if o not in local.tax_map:
                            continue
                        skip_m = SKIP_RE.match(o)
                        if local.tax:
                            if (local.tax == 'domain') and skip_m:
                                continue
                            local.org_map[local.tax][local.tax_map[o]] += md5s[rec['md5']]
                        else:
                            for i, _ in enumerate(taxa):
                                if (taxa[i] == 'domain') and skip_m:
                                    continue
                                local.org_map[taxa[i]][local.tax_map[o][i]] += md5s[rec['md5']]
        
        total = 0
        count = 0
        prev = time.time()
        md5s = {}
        rows = self.jobs.get_job_records(job, ['md5', 'abundance'])
        for r in rows:
            md5s[r[0]] = r[1]
            count += 1
            total += 1
            if count == self.chunk:
                add_annotations(md5s)
                md5s = {}
                count = 0
            if (total % 1000) == 0:
                prev = self.update_progress(node, total, local.found, prev)
        if count > 0:
            add_annotations(md5s)
        self.update_progress(node, total, local.found, 0) # last update
        return [total, local.org_map, local.fun_map, local.ont_map]
    
    # only update if been more than UPDATE_SECS
    def update_progress(self, node, total, found, prev):
        now = time.time()
        if self.shock and node and (now > (prev + UPDATE_SECS)):
            attr = node['attributes']
            attr['progress']['queried'] = total
            attr['progress']['found'] = found
            if prev == 0:
                # final update
                attr['progress']['completed'] = 'annotation'
            self.shock.upload(node=node['id'], attr=json.dumps(attr))
            return now
        else:
            return prev
    
