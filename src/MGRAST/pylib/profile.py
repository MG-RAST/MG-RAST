import re
import time
from collections import defaultdict
from mgrast_cassandra import *
from shock import ShockClient

M5NR_VERSION = 1
CHUNK_SIZE = 2000

class Profile(object):
    def __init__(self, hosts, version=M5NR_VERSION, chunk=CHUNK_SIZE):
        self.m5nr = M5nrHandle(hosts, version)
        self.jobs = JobHandle(hosts, version)
        self.chunk = chunk
        self.shock = None
        set_ontology()
    
    def set_ontology(self, sources=['Subsystems', 'NOG', 'COG', 'KO']):
        self.ontology = sources
    
    def set_shock(self, url='http://shock.metagenomics.anl.gov', bearer='mgrast', token=None):
        self.shock = ShockClient(shock_url=url, bearer=bearer, token=token)
    
    def close():
        close_cluster()
    
    ## requires shock node (with correct attributes) for storing temperary data
    # node['attributes'] = {
    #    id :
    #    job_id :
    #    source :
    #    format :
    #    condensed :
    #    version :
    #}
    def compute_profile(self, node, attr=None):
        jobid   = node['attributes']['job_id']
        source  = node['attributes']['source']
        index   = True if node['attributes']['condensed'] eq 'true' else False
        profile = None
        
        if node['attributes']['format'] == 'biom':
            profile = init_biom_profile(node['attributes']['id'])
            rows, data = get_biom_data(job, source)
            profile['rows'] = rows
            profile['data'] = data
            profile['shape'][0] = len(profile['rows'])
        elif node['attributes']['format'] == 'mgrast':
            profile = init_mgrast_profile(node['attributes']['id'], source, index)
            data = get_mgrast_data(job, source, index, node)
            profile['data'] = data
            profile['row_total'] = len(profile['data'])
        
        if attr not None:
            # store as permanent shock node
            
        else:
            # store as temp shock node
            
    
    def init_mgrast_profile(self, mgid, source, index=False):
        return {
            'id'        : mgid,
            'created'   : datetime.datetime.now().isoformat(),
            'version'   : M5NR_VERSION,
            'source'    : source,
            'columns'   : ["md5sum", "abundance", "e-value", "percent identity", "alignment length", "organisms", "functions"],
            'condensed' : 'true' if index else 'false',
            'row_total' : 0,
            'data'      : []
	    }    
    
    def init_biom_profile(self, mgid):
        return {
            'id'                  : mgid,
            'format'              : "Biological Observation Matrix 1.0",
            'format_url'          : "http://biom-format.org",
            'type'                : "Feature table",
            'generated_by'        : "MG-RAST",
            'date'                : datetime.datetime.now().isoformat(),
            'matrix_type'         : "dense",
            'matrix_element_type' : "float",
            'shape'               : [ 0, 4 ],
            'rows'                : [],
            'data'                : [],
            'columns'             : [
                {'id' : "abundance"},
                {'id' : "e-value"},
                {'id' : "percent identity"},
                {'id' : "alignment length"}
            ]
        }
    
    def get_mgrast_data(self, job, source, index=False, node=None):
        data = []
        found = 0
        md5_row = defaultdict(list)
        
        def append_profile(found, data, md5_row):
            md5_idx = {}
            ann_data = self.m5nr.get_records_by_md5(md5_row.keys(), source=source, index=index, iterator=True)
            for info in ann_data:
                if info['md5'] not in md5_idx:
                    found += 1
                    data.append(md5_row[info['md5']])
                    idx = len(data) - 1
                    md5_idx[info['md5']] = idx
                idx = md5_idx[info['md5']]
                # add annotations to data matrix
                # md5sum, abundance, e-value, percent identity, alignment length, organisms (first is single), functions (either function or ontology)
                if info['single'] and info['organism']:
                    orgs = info['organism']
                    try:
                        orgs.remove(info['single'])
                    except ValueError:
                        pass
                    orgs.insert(0, info['single'])
                    data[idx][5] = orgs
                if (source in self.ontology) and info['accession']:
                    data[idx][6] = info['accession']
                elif info['function']
                    data[idx][6] = info['function']
            return found, data
        
        total = 0
        count = 0
        rows = self.jobs.get_job_records(job, ['md5', 'abundance', 'exp_avg', 'ident_avg', 'len_avg'])
        for r in rows:
            md5_row[r[0]] = [r[0], r[1], r[2], r[3], r[4], None, None]
            total += 1
            count += 1
            if count == self.chunk:
                found, data = append_profile(found, data, md5_row)
                md5_row = defaultdict(list)
                count = 0
            if self.shock and node and ((total % 100000) == 0):
                attr = node['attributes']
                attr['progress']['queried'] = total
                attr['progress']['found'] = found
                node = self.shock.upload(node=node['id'], attr=attr)
        if count > 0:
            found, data = append_profile(found, data, md5_row)
        if self.shock and node:
            attr = node['attributes']
            attr['progress']['queried'] = total
            attr['progress']['found'] = found
            self.shock.upload(node=node['id'], attr=attr)
        return data
    
    def get_biom_data(self, job, source):
        rows = []
        data = []
        md5_row = defaultdict(list)
        
        def append_profile(rows, data, md5_row):
            md5_idx = {}
            ann_data = self.m5nr.get_records_by_md5(md5_row.keys(), source=source, index=False, iterator=True)
            for info in ann_data:
                if info['md5'] not in md5_idx:
                    found += 1
                    rows.append({'id': info['md5'], 'metadata': {}})
                    data.append(md5_row[info['md5']])
                    idx = len(data) - 1
                    md5_idx[info['md5']] = idx
                idx = md5_idx[info['md5']]
                # add annotations to row metadata
                rows[idx]['metadata'] = { 'source': source, 'function': info['function'] }
                if info['source'] in self.ontology:
                    rows[idx]['metadata']['ontology'] = info['accession']
                else:
                    rows[idx]['metadata']['single'] = info['single']
                    rows[idx]['metadata']['organism'] = info['organism']
                    if info['accession']:
                        rows[idx]['metadata']['accession'] = info['accession']
            return rows, data
        
        total = 0
        count = 0
        rows = self.jobs.get_job_records(job, ['md5', 'abundance', 'exp_avg', 'ident_avg', 'len_avg'])
        for r in rows:
            md5_row[r[0]] = [r[1], r[2], r[3], r[4]]
            total += 1
            count += 1
            if count == self.chunk:
                rows, data = append_profile(rows, data, md5_row)
                md5_row = defaultdict(list)
                count = 0
        if count > 0:
            rows, data = append_profile(rows, data, md5_row)
        return rows, data
    
