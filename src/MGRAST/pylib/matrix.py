
import sys
import datetime
import json
import shock
import mgrast_cassandra
from collections import defaultdict

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
    
    def compute_matrix(self, param, node=None):
        matrix = None
        ## compute matrix
        try:
            matrix = self.init_matrix(param['id'], param['url'], param['type'], param['source'], param['source_type'], param['result_type'])
            for mg in param['mg_ids']:
                metadata = param['metadata'][mg] if mg in param['metadata'] else None
                profile['columns'].append({'id': mg, 'metadata', metadata})
            rows, data = self.get_data(param, node)
            profile['rows']  = rows
            profile['data']  = data
            profile['shape'] = [ len(profile['rows']), len(param['mg_ids']) ]
        except:
            self.error_exit("unable to build BIOM profile", node)
            return
        ## store file in node or return string
        if node:
            self.shock.upload(node=node['id'], data=json.dumps(matrix), file_name=param['id']+".biom")
            return None
        else:
            return json.dumps(matrix)
    
    def error_exit(self, error, node=None):
        if node:
            # save error to node
            data = {'ERROR': error, "STATUS": 500}
            self.shock.upload(node=node['id'], data=json.dumps(data), file_name='error')
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
    
    def get_data(self, param, node=None):
        rows = []
        data = []
        found = 0
        md5_row = {}
        # group_map = None if not leaf_node
        group_map = self.get_group_map(param['type'], param['hit_type'], param['group_level'], param['leaf_node'], param['source'])
        # filter_list = None if not leaf_filter and no filter text
        filter_list = self.get_filter_list(param['type'], param['filter'], param['filter_level'], param['filter_source'], param['leaf_filter'])
        # ann_type = one of: organism, function, accession, single
        ann_type = param['type']
        if param['type'] == 'ontology':
            ann_type = 'accession'
        elif (param['type'] == 'organism') and (param['hit_type'] != 'all'):
            ann_type = 'single'
        
        def append_matrix(found, rows, data, md5_row, col):
            ann_idx = {}
            # get filter md5s / skip empty
            if filter_list and param['filter_source']:
                qmd5s = get_filter_md5s(md5_row.keys(), param['type'], filter_list, param['filter_source'])
            else:
                qmd5s = md5_row.keys()
            if len(qmd5s) == 0:
                return found, rows, data
            
            ann_data = self.m5nr.get_records_by_md5(qmd5s, source=source, index=False, iterator=True)
            for info in ann_data:                
                # get annotations based on type & hit_type
                annotations = [];
                if param['type'] == 'function':
                    annotations = info['function']
                elif param['type'] == 'ontology':
                    annotations = info['ontology']
                elif param['type'] == 'organism':
                    if param['hit_type'] == 'all':
                        annotations = info['organism']
                    elif param['hit_type'] == 'single':
                        annotations = [ info['single'] ];
                    elif param['hit_type'] == 'lca':
                        my $taxa = $set->{lca}[$group_map];
                        next if ($taxa =~ /^\-/);
                        $annotations = [ $taxa ];
                    }
                }
                # grouping
                if (defined($group_map) && ($htype ne 'lca')) {
                    my %unique = map { $group_map->{$_}, 1 } grep { exists($group_map->{$_}) } @$annotations;
                    $annotations = [ keys %unique ];
                }
                
                
                if ann_type == 'single':
                    # cast string into array so type is consistant
                    ann_list = [ ann_list ]
                for a in ann_list:
                    # this is base / leaf value
                    val = a
                    if group_map:
                        # get annotation up hierarchy
                        val = group_map[a] if a in group_map else None
                    if not val:
                        continue
                    if val not in ann_idx:
                        found += 1
                        rows.append({'id': val, 'metadata': {}})
                #####################    
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
            # TODO: stuff
            return found, rows, data
        
        total = 0
        count = 0
        for col, job in enumerate(param['job_ids']):
            recs  = self.jobs.get_job_records(job, ['md5', RESULT_MAP[param['result_type']]], param['evalue'], param['identity'], param['length'])
            for r in recs:
                md5_row[r[0]] = r[1]
                total += 1
                count += 1
                if count == self.chunk:
                    found, rows, data = append_matrix(found, rows, data, md5_row, col)
                    md5_row = {}
                    count = 0
                if (total % 100000) == 0:
                    self.update_progress(node, total, found)
            if count > 0:
                found, rows, data = append_matrix(found, rows, data, md5_row, col)
            self.update_progress(node, total, found)
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
    
    def update_progress(self, node, total, found):
        if self.shock and node:
            attr = node['attributes']
            attr['progress']['queried'] = total
            attr['progress']['found'] = found
            self.shock.upload(node=node['id'], attr=json.dumps(attr))
    
