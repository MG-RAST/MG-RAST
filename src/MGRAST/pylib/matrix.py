
import sys
import time
import datetime
import json
import shock
import operator
import mgrast_cassandra
from collections import defaultdict

UPDATE_SECS  = 300
M5NR_VERSION = 1
CHUNK_SIZE = 100
TAXONOMY   = ['domain', 'phylum', 'class', 'order', 'family', 'genus', 'species', 'strain']
RESULT_MAP = {
    'abundance' : 'abundance',
    'evalue'    : 'exp_avg',
    'length'    : 'len_avg',
    'identity'  : 'ident_avg'
}

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
    
    def compute_matrix(self, node, param, metadata, hierarchy):
        matrix = None
        ## compute matrix
        try:
            matrix = self.init_matrix(param['id'], param['url'], param['type'], param['source'], param['source_type'], param['result_type'])
            for mg in param['mg_ids']:
                mdata = metadata[mg] if mg in metadata else None
                matrix['columns'].append({'id': mg, 'metadata': mdata})
            rows, data = self.get_data(node, param, hierarchy)
            matrix['rows']  = rows
            matrix['data']  = data
            matrix['shape'] = [ len(matrix['rows']), len(matrix['columns']) ]
        except Exception as ex:
            self.error_exit("unable to build BIOM profile", node, ex)
            return
        ## store file in node
        self.shock.upload(node=node['id'], data=json.dumps(matrix), file_name=param['id']+".biom")
        return None
    
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
    
    def get_data(self, node, param, hierarchy):
        found = 0
        data  = []
        row_len = len(param['job_ids'])
        row_idx = {} # row_id : row_idx
        md5_val = {} # md5 : value
        # group_map = None if not leaf_node
        group_map = self.get_group_map(param['type'], param['hit_type'], param['group_level'], param['leaf_node'], param['source'])
        # filter_list = None if not leaf_filter and no filter text
        filter_list = self.get_filter_list(param['type'], param['filter'], param['filter_level'], param['filter_source'], param['leaf_filter'])
        
        def append_matrix(cindex, md5_val, found, data, row_idx):
            next_idx = len(row_idx) # incraments row idx
            # get filter md5s / skip empty
            if filter_list and param['filter_source']:
                qmd5s = self.get_filter_md5s(md5_val.keys(), param['type'], filter_list, param['filter_source'])
            else:
                qmd5s = md5_val.keys()
            if len(qmd5s) == 0:
                return found, data, row_idx
            
            ann_data = self.m5nr.get_records_by_md5(qmd5s, source=param['source'], index=False, iterator=True)
            for info in ann_data:                
                # get annotations based on type & hit_type
                # one of type: organism, function, accession, single
                annotations = [];
                if param['type'] == 'function':
                    annotations = info['function']
                elif param['type'] == 'ontology':
                    annotations = info['accession']
                elif param['type'] == 'organism':
                    if param['hit_type'] == 'all':
                        annotations = info['organism']
                    elif param['hit_type'] == 'single':
                        annotations = [ info['single'] ];
                    elif param['hit_type'] == 'lca':
                        try:
                            taxa = info['lca'][group_map]
                            if taxa.startswith('-'):
                                continue
                            annotations = [ taxa ]
                        except Exception:
                            continue
                # grouping
                if group_map and (param['hit_type'] != 'lca'):
                    unique = set()
                    for a in annotations:
                        if a in group_map:
                            unique.add(group_map[a])
                    annotations = list(unique)
                # loop through annotations for row index
                for a in annotations:
                    if a in row_idx:
                        # alrady saw this annotation
                        rindex = row_idx[a]
                    else:
                        # new annotation, add to rows
                        rindex = next_idx
                        row_idx[a] = rindex
                        if param['result_type'] == 'abundance':
                            # populate data with zero's
                            data.append([0 for _ in range(row_len)])
                        else:
                            # populate data with tuple of zero's
                            data.append([(0,0) for _ in range(row_len)])
                        next_idx += 1
                    # get md5 value for job
                    # curr is int if abundance, tuple otherwise
                    if info['md5'] in md5_val:
                        curr = data[rindex][cindex]
                        data[rindex][cindex] = self.add_value(curr, md5_val[info['md5']], param['result_type'])
            return found, data, row_idx
        
        # loop through jobs
        for cindex, job in enumerate(param['job_ids']):
            total = 0
            count = 0
            prev  = time.time()
            recs  = self.jobs.get_job_records(job, ['md5', RESULT_MAP[param['result_type']]], param['evalue'], param['identity'], param['length'])
            # loop through md5 values
            for r in recs:
                md5_val[r[0]] = r[1]
                total += 1
                count += 1
                if count == self.chunk:
                    found, data, row_idx = append_matrix(cindex, md5_val, found, data, row_idx)
                    md5_val = {}
                    count = 0
                if (total % 1000) == 0:
                    prev = self.update_progress(node, job, total, found, prev)
            if count > 0:
                found, data, row_idx = append_matrix(cindex, md5_val, found, data, row_idx)
            prev = self.update_progress(node, job, total, found, 0) # last update for this job
        
        # transform [ count, sum ] to single average
        if param['result_type'] != 'abundance':
            for row in data:
                for i in range(row_len):
                    (n, s) = row[i]
                    if n == 0:
                        row[i] = 0
                    else:
                        row[i] = round((s / n), 3)
        
        # build rows
        rows = []
        for r, i in sorted(row_idx.items(), key=operator.itemgetter(1)):
            rows.append({'id' : r, 'metadata' : None})
            
        # add row metadata / hierarchy
        if param['hier_match'] and (len(hierarchy) > 0):
            for r in rows:
                for h in hierarchy:
                    if param['hier_match'] not in h:
                        continue
                    if r['id'] == h[param['hier_match']]:
                        if 'organism' in h:
                            h['strain'] = h['organism']
                            del h['organism']
                        if 'accession' in h:
                            del h['accession']
                        if 'ncbi_tax_id' in h:
                            tid = h['ncbi_tax_id']
                            del h['ncbi_tax_id']
                            r['metadata'] = { 'hierarchy': h, 'ncbi_tax_id': tid }
                        else:
                            r['metadata'] = { 'hierarchy': h }
                        break
        # done
        return rows, data
    
    # get grouping map: leaf_name => group_name
    # index of taxonomy if lca
    def get_group_map(self, mtype, htype, glevel, leaf, source):
        if not leaf:
            if mtype == 'organism':
                if htype != 'lca':
                    return self.m5nr.get_org_taxa_map(glevel)
                else:
                    try:
                        return TAXONOMY.index(glevel)
                    except Exception:
                        return 0
            elif mtype == 'ontology':
                return self.m5nr.get_ontology_map(glevel, source)
        return None
    
    # get filter list: all leaf names that match filter for given filter_level (organism, ontology only)
    def get_filter_list(self, mtype, ftext, flevel, fsource, fleaf):
        if ftext and (not fleaf):
            if mtype == 'organism':
                return self.m5nr.get_organism_by_taxa(flevel, ftext)
            elif mtype == 'ontology':
                return self.m5nr.get_ontology_by_level(fsource, flevel, ftext)
        return None
    
    # get subset of md5s based on filter list / source
    def get_filter_md5s(self, md5s, mtype, flist, fsource):
        fmd5s = []
        field = 'accession' if mtype == 'ontology' else 'organism'
        recs  = self.m5nr.get_records_by_md5(md5s, source=fsource, index=False, iterator=True)
        for r in recs:
            for a in r[field]:
                if a in flist:
                    fmd5s.append(r['md5'])
        return fmd5s
    
    # sum if abundance, [ count, sum ] if other
    def add_value(self, curr, val, rtype):
        if rtype == 'abundance':
            # return sum
            return curr + val
        else:
            # return tuple of count, sum
            return ( curr[0]+1, curr[1]+val )
    
    # only update if been more than UPDATE_SECS
    def update_progress(self, node, job, total, found, prev):
        now = time.time()
        if self.shock and node and (now > (prev + UPDATE_SECS)):
            attr = node['attributes']
            if job in attr['progress']:
                attr['progress'][job]['queried'] = total
                attr['progress'][job]['found'] = found
                if prev == 0:
                    # final update
                    attr['progress'][job]['completed'] = 1
            self.shock.upload(node=node['id'], attr=json.dumps(attr))
            return now
        else:
            return prev
    
