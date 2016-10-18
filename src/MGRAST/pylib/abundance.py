import re
from collections import defaultdict
from mgrast_cassandra import *

M5NR_VERSION = 1
CHUNK_SIZE = 2000
SKIP_RE = re.compile('other|unknown|unclassified')

class Abundance(object):
    def __init__(self, hosts, version=M5NR_VERSION, chunk=CHUNK_SIZE):
        self.m5nr = M5nrHandle(hosts, version)
        self.jobs = JobHandle(hosts, version)
        self.chunk = chunk
    
    def close():
        close_cluster()
    
    def all_md5s(self, job):
        md5s = []
        rows = self.jobs.get_job_records(job, ['md5'])
        for r in rows:
            md5s.append(r[0])
        return md5s
    
    def all_annotation_abundances(self, job, taxa=[], org=0, fun=0, ont=0):
        class local:
            tax = ""
            tax_map = {}
            org_map = defaultdict(lambda: defaultdict(int)) # tax_lvl : taxa : abundance
            fun_map = defaultdict(int)   # func : abundance
            ont_map = {}                 # source : level1 : accession : abundance
            ont_cat = {}                 # source : ont : level1
        
        if org and (len(taxa) == 1):
            local.tax = taxa[0]
            # org : taxa
            local.tax_map = self.m5nr.get_org_taxa_map(local.tax)
            local.org_map[tax] = {}
        elif org and (len(taxa) > 1):
            # org : [ taxa ]
            local.tax_map = self.m5nr.get_taxa_hierarchy()
            for t in taxa:
                local.org_map[t] = {}
        if ont:
            local.ont_cat = self.m5nr.get_ontology_hierarchy()
        
        def add_annotations(md5s):
            records = self.m5nr.get_records_by_md5(md5s.keys(), iterator=True)
            for rec in records:
                if fun and rec['function']:
                    for f in rec['function']:
                        local.fun_map[f] += md5s[rec['md5']]
                if ont and (rec['source'] in local.ont_cat) and rec['accession']:
                    if rec['source'] not in local.ont_map:
                        local.ont_map[rec['source']] = defaultdict(lambda: defaultdict(int))
                    for a in rec['accession']:
                        local.ont_map[rec['source']][local.ont_cat[rec['source']]][a] += md5s[rec['md5']]
                if org and rec['organism']:
                    for o in rec['organism']:
                        skip_m = SKIP_RE.match(o)
                        if local.tax:
                            if (local.tax == 'domain') and skip_m:
                                continue
                            local.org_map[taxa[0]][local.tax_map[o]] += md5s[rec['md5']]
                        else:
                            for i, t enumerate(taxa):
                                if (taxa[i] == 'domain') and skip_m:
                                    continue
                                local.org_map[taxa[i]][local.tax_map[o][i]] += md5s[rec['md5']]
        
        total = 0
        count = 0
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
        if count > 0
            add_annotations(md5s)
        
        return [total, local.org_map, local.fun_map, local.ont_map]
    
