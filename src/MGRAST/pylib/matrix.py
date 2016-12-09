
import datetime
import json
import shock
import mgrast_cassandra
from collections import defaultdict

M5NR_VERSION = 1
CHUNK_SIZE = 100

class Matrix(object):
    def __init__(self, hosts, version=M5NR_VERSION, chunk=CHUNK_SIZE):
        self.m5nr = mgrast_cassandra.M5nrHandle(hosts, version)
        self.jobs = mgrast_cassandra.JobHandle(hosts, version)
        self.chunk = int(chunk)
        self.shock = None
        self.version = int(version)
        self.set_ontology()
    
    def set_ontology(self, sources=['Subsystems', 'NOG', 'COG', 'KO']):
        self.ontology = sources
    
    def set_shock(self, token=None, bearer='mgrast', url='http://shock.metagenomics.anl.gov'):
        self.shock = shock.ShockClient(shock_url=url, bearer=bearer, token=token)
    
    def close(self):
        self.m5nr.close()
        self.jobs.close()
    
    def compute_matrix(self, node, param):
        matrix = None
        ## compute matrix
        try:
            matrix = self.init_matrix(param['id'], param['url'], param['type'], param['source'], param['source_type'], param['result_type'])
            for mg in param['mg_ids']:
                metadata = param['metadata'][mg] if mg in param['metadata'] else None
                profile['columns'].append({'id': mg, 'metadata', metadata})
                profile['shape'][1] += 1
            rows, data = self.get_data(param['job_ids'], param['source'], node)
            profile['rows'] = rows
            profile['data'] = data
            profile['shape'][0] = len(profile['rows'])
        except:
            self.error_exit("unable to build BIOM profile", node)
            return
        ## store file in node
        self.shock.upload(node=node['id'], data=json.dumps(matrix), file_name=param['id']+".biom")
        return
    
    def error_exit(self, error, node=None):
        if node:
            # save error to node
            data = {'ERROR': error, "STATUS": 500}
            self.shock.upload(node=node['id'], data=json.dumps(data), file_name='error')
        self.close()
    
    def init_matrix(self, mid, murl, mtype, source, stype, rtype):
        return {
            'id'                  : mid,
            'url'                 : murl,
            'format'              : "Biological Observation Matrix 1.0",
            'format_url'          : "http://biom-format.org",
            'type'                : "Taxon table" if mtype == 'organism' else "Function table",
            'data_source'         : source,
            'source_type'         : stype,
            'generated_by'        : "MG-RAST",
            'date'                : datetime.datetime.now().isoformat(),
            'matrix_type'         : "dense",
            'matrix_element_type' : "int" if rtype == 'abundance' else "float",
            'matrix_element_value': rtype,
            'shape'               : [0, 0],
            'rows'                : [],
            'columns'             : [],
            'data'                : []
        }
    
    def get_data(self, jobs, source, node=None):
        # TODO: stuff
        return None
    
    def update_progress(self, node, total, found):
        if self.shock and node:
            attr = node['attributes']
            attr['progress']['queried'] = total
            attr['progress']['found'] = found
            self.shock.upload(node=node['id'], attr=json.dumps(attr))
    
