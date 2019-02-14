
import sys
import time
import datetime
import json
import shock
import mgrast_cassandra
from collections import defaultdict

UPDATE_SECS  = 300
M5NR_VERSION = 1
CHUNK_SIZE   = 100

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
    
    def set_shock(self, token=None, bearer='mgrast', url='http://shock.mg-rast.org'):
        self.shock = shock.ShockClient(shock_url=url, bearer=bearer, token=token)
    
    def close(self):
        self.m5nr.close()
        self.jobs.close()
    
    def compute_profile(self, node, param, attr=None):
        swap    = True if ('swap' in param) and param['swap'] else False
        index   = True if param['condensed'] == 'true' else False
        fname   = "%s_%s_v%d.%s"%(param['id'], param['source'], self.version, param['format'])
        profile = None
        
        ## if we throw an error, save it in shock node
        if param['format'] == 'mgrast':
            try:
                profile = self.init_mgrast_profile(param['id'], param['source'], param['source_type'], index)
                data    = self.get_mgrast_data(param['job_id'], param['source'], index, node, swap)
                profile['data'] = data
                profile['row_total'] = len(profile['data'])
            except Exception as ex:
                self.error_exit("unable to build mgrast profile", node, ex)
                return
        elif param['format'] == 'lca':
            try:
                profile = self.init_lca_profile(param['id'])
                data    = self.get_lca_data(param['job_id'], node, swap)
                profile['data'] = data
                profile['row_total'] = len(profile['data'])
            except Exception as ex:
                self.error_exit("unable to build lca profile", node, ex)
                return
        elif param['format'] == 'biom':
            try:
                profile    = self.init_biom_profile(param['id'], param['source'], param['source_type'])
                rows, data = self.get_biom_data(param['job_id'], param['source'], node, swap)
                profile['rows'] = rows
                profile['data'] = data
                profile['shape'][0] = len(profile['rows'])
            except Exception as ex:
                self.error_exit("unable to build BIOM profile", node, ex)
                return
        else:
            self.error_exit("unable to build profile, invalid format", node)
        
        ## sanity check
        if len(profile['data']) == 0:
            self.error_exit("unable to build profile, no data returned", node)
            return
        
        ## permanent: update attributes / remove expiration
        if attr:
            attr['row_total'] = profile['row_total'] if 'row_total' in profile else profile['shape'][0]
            if param['format'] == 'lca':
                attr['lca_queried'] = node['attributes']['progress']['queried']
                attr['lca_found']   = node['attributes']['progress']['found']
            else:
                attr['md5_queried'] = node['attributes']['progress']['queried']
                attr['md5_found']   = node['attributes']['progress']['found']
            try:
                self.shock.upload(node=node['id'], attr=json.dumps(attr))
                self.shock.update_expiration(node['id'])
                if attr['status'] == 'public':
                    self.shock.add_acl(node=node['id'], acl='read', public=True)
            except Exception as ex:
                self.error_exit("unable to update profile shock node "+node['id'], node, ex)
                return
        
        ## store file in node
        self.shock.upload(node=node['id'], data=json.dumps(profile), file_name=fname)
        return
    
    def error_exit(self, error, node=None, ex=None):
        if ex:
            error += ": an exception of type {0} occured. Arguments:\n{1!r}".format(type(ex).__name__, ex.args)
        if node:
            # save error to node
            data = {'ERROR': error, "STATUS": 500}
            self.shock.upload(node=node['id'], data=json.dumps(data), file_name='error')
            self.shock.update_expiration(node['id'], expiration='1D')
        else:
            sys.stderr.write(error+"\n")
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
    
    def init_lca_profile(self, mgid):
        return {
            'id'          : mgid,
            'created'     : datetime.datetime.now().isoformat(),
            'version'     : self.version,
            'source'      : 'LCA',
            'columns'     : ["lca", "abundance", "e-value", "percent identity", "alignment length", "md5s", "level"],
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
                {'id': "abundance", 'metadata': None},
                {'id': "e-value", 'metadata': None},
                {'id': "percent identity", 'metadata': None},
                {'id': "alignment length", 'metadata': None}
            ]
        }
    
    def get_mgrast_data(self, job, source, index=False, node=None, swap=False):
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
        prev  = time.time()
        recs  = self.jobs.get_job_records(job, ['md5', 'abundance', 'exp_avg', 'ident_avg', 'len_avg'])
        for r in recs:
            if swap:
                md5_row[r[0]] = [r[0], r[1], r[2], r[4], r[3], None, None]
            else:
                md5_row[r[0]] = [r[0], r[1], r[2], r[3], r[4], None, None]
            total += 1
            count += 1
            if count == self.chunk:
                found, data = append_profile(found, data, md5_row)
                md5_row = defaultdict(list)
                count = 0
            if (total % 1000) == 0:
                prev = self.update_progress(node, total, found, prev)
        if count > 0:
            found, data = append_profile(found, data, md5_row)
        self.update_progress(node, total, found, 0) # last update
        return data
    
    def get_lca_data(self, job, node=None, swap=False):
        data  = []
        found = 0
        total = 0
        prev  = time.time()
        recs  = self.jobs.get_lca_records(job, ['lca', 'abundance', 'exp_avg', 'ident_avg', 'len_avg', 'md5s', 'level'])
        for r in recs:
            total += 1
            if not r[0]:
                continue
            if swap:
                data.append([r[0], r[1], r[2], r[4], r[3], r[5], r[6]])
            else:
                data.append([r[0], r[1], r[2], r[3], r[4], r[5], r[6]])
            found += 1
            if (total % 1000) == 0:
                prev = self.update_progress(node, total, found, prev)
        self.update_progress(node, total, found, 0) # last update
        return data
    
    def get_biom_data(self, job, source, node=None, swap=False):
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
        prev  = time.time()
        recs  = self.jobs.get_job_records(job, ['md5', 'abundance', 'exp_avg', 'ident_avg', 'len_avg'])
        for r in recs:
            if swap:
                md5_row[r[0]] = [r[1], r[2], r[4], r[3]]
            else:
                md5_row[r[0]] = [r[1], r[2], r[3], r[4]]
            total += 1
            count += 1
            if count == self.chunk:
                found, rows, data = append_profile(found, rows, data, md5_row)
                md5_row = defaultdict(list)
                count = 0
            if (total % 1000) == 0:
                prev = self.update_progress(node, total, found, prev)
        if count > 0:
            found, rows, data = append_profile(found, rows, data, md5_row)
        self.update_progress(node, total, found, 0) # last update
        return rows, data
    
    # only update if been more than UPDATE_SECS
    def update_progress(self, node, total, found, prev):
        now = time.time()
        if self.shock and node and (now > (prev + UPDATE_SECS)):
            attr = node['attributes']
            attr['progress']['queried'] = total
            attr['progress']['found'] = found
            if prev == 0:
                # final update
                attr['progress']['completed'] = 1
            self.shock.upload(node=node['id'], attr=json.dumps(attr))
            return now
        else:
            return prev
    
