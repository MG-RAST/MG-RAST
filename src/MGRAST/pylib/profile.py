
import datetime
import json
import shock
import mgrast_cassandra
from collections import defaultdict

M5NR_VERSION = 1
CHUNK_SIZE = 500

class Profile(object):
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
    
    def compute_profile(self, node, param, attr=None):
        index   = True if param['condensed'] == 'true' else False
        fname   = "%s_%s_v%d.%s"%(param['id'], param['source'], self.version, param['format'])
        profile = None
        
        ## if we throw an error, save it in shock node
        if param['format'] == 'biom':
            try:
                profile    = self.init_biom_profile(param['id'], param['source'], param['source_type'])
                rows, data = self.get_biom_data(param['job_id'], param['source'])
                profile['rows'] = rows
                profile['data'] = data
                profile['shape'][0] = len(profile['rows'])
            except:
                self.error_exit("unable to build BIOM profile", node)
                return
        elif param['format'] == 'mgrast':
            try:
                profile = self.init_mgrast_profile(param['id'], param['source'], param['source_type'], index)
                data    = self.get_mgrast_data(param['job_id'], param['source'], index, node)
                profile['data'] = data
                profile['row_total'] = len(profile['data'])
            except:
                self.error_exit("unable to build mgrast profile", node)
                return
        else:
            self.error_exit("unable to build profile, invalid format", node)
        
        ## permanent: update attributes / remove expiration
        if attr:
            attr['row_total']   = profile['row_total'] if 'row_total' in profile else profile['shape'][0]
            attr['md5_queried'] = node['attributes']['progress']['queried']
            attr['md5_found']   = node['attributes']['progress']['found']
            try:
                self.shock.upload(node=node['id'], attr=json.dumps(attr))
                self.shock.update_expiration(node['id'])
                if attr['status'] == 'public':
                    self.shock.add_acl(node=node['id'], acl='read', public=True)
            except:
                self.error_exit("unable to update profile shock node "+node['id'], node)
                return
        
        ## store file in node
        self.shock.upload(node=node['id'], data=json.dumps(profile), file_name=fname)
        return
    
    def error_exit(self, error, node=None):
        if node:
            # save error to node
            data = {'ERROR': error, "STATUS": 500}
            self.shock.upload(node=node['id'], data=json.dumps(data), file_name='error')
        self.close()
    
    def init_mgrast_profile(self, mgid, source, stype, index=False):
        return {
            'id'          : mgid,
            'created'     : datetime.datetime.now().isoformat(),
            'version'     : self.version,
            'source'      : source,
            'source_type' : stype,
            'columns'     : ["md5sum", "abundance", "e-value", "percent identity", "alignment length", "organisms", "functions"],
            'condensed'   : 'true' if index else 'false',
            'row_total'   : 0,
            'data'        : []
	    }    
    
    def init_biom_profile(self, mgid, source, stype):
        return {
            'id'                  : mgid,
            'format'              : "Biological Observation Matrix 1.0",
            'format_url'          : "http://biom-format.org",
            'type'                : "Feature table",
            'data_source'         : source,
            'source_type'         : stype,
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
                elif info['function']:
                    data[idx][6] = info['function']
            return found, data
        
        total = 0
        count = 0
        recs  = self.jobs.get_job_records(job, ['md5', 'abundance', 'exp_avg', 'ident_avg', 'len_avg'])
        for r in recs:
            md5_row[r[0]] = [r[0], r[1], r[2], r[3], r[4], None, None]
            total += 1
            count += 1
            if count == self.chunk:
                found, data = append_profile(found, data, md5_row)
                md5_row = defaultdict(list)
                count = 0
            if (total % 100000) == 0:
                self.update_progress(node, total, found)
        if count > 0:
            found, data = append_profile(found, data, md5_row)
        self.update_progress(node, total, found)
        return data
    
    def get_biom_data(self, job, source, node=None):
        rows = []
        data = []
        found = 0
        md5_row = defaultdict(list)
        
        def append_profile(found, rows, data, md5_row):
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
                rows[idx]['metadata'] = { 'function': info['function'] }
                if info['source'] in self.ontology:
                    rows[idx]['metadata']['ontology'] = info['accession']
                else:
                    rows[idx]['metadata']['single'] = info['single']
                    rows[idx]['metadata']['organism'] = info['organism']
                    if info['accession']:
                        rows[idx]['metadata']['accession'] = info['accession']
            return found, rows, data
        
        total = 0
        count = 0
        recs  = self.jobs.get_job_records(job, ['md5', 'abundance', 'exp_avg', 'ident_avg', 'len_avg'])
        for r in recs:
            md5_row[r[0]] = [r[1], r[2], r[3], r[4]]
            total += 1
            count += 1
            if count == self.chunk:
                found, rows, data = append_profile(found, rows, data, md5_row)
                md5_row = defaultdict(list)
                count = 0
            if (total % 100000) == 0:
                self.update_progress(node, total, found)
        if count > 0:
            found, rows, data = append_profile(found, rows, data, md5_row)
        self.update_progress(node, total, found)
        return rows, data
    
    def update_progress(self, node, total, found):
        if self.shock and node:
            attr = node['attributes']
            attr['progress']['queried'] = total
            attr['progress']['found'] = found
            self.shock.upload(node=node['id'], attr=json.dumps(attr))
    
