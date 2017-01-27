#!/usr/bin/env python

import sys
import json
import urllib2
from operator import itemgetter
from optparse import OptionParser
from prettytable import PrettyTable

AWE_URL = 'http://awe.metagenomics.anl.gov'
MGP = { 'mgrast-prod': [
    'qc_stats',
    'preprocess',
    'dereplication',
    'screen',
    'rna detection',
    'rna clustering',
    'rna sims blat',
    'genecalling',
    'aa filtering',
    'aa clustering',
    'aa sims blat',
    'aa sims annotation',
    'rna sims annotation',
    'index sim seq',
    'md5 abundance',
    'lca abundance',
    'source abundance',
    'abundance cassandra load',
    'done stage',
    'notify job completion'
] }

def get_awe(url, token):
    header = {'Accept': 'application/json', 'Authorization': 'mgrast '+token}
    req = urllib2.Request(url, headers=header)
    res = urllib2.urlopen(req)
    obj = json.loads(res.read())
    return obj['data']

def main(args):
    global AWE_URL
    parser = OptionParser(usage='awe_viewer.py [options]')
    parser.add_option("-a", "--awe_url", dest="awe_url", default=AWE_URL, help="AWE API url")
    parser.add_option("-t", "--token", dest="token", default=None, help="User token")
    parser.add_option("-c", "--clientgroup", dest="clientgroup", default=None, help="clientgroup to view")
    parser.add_option("-p", "--pipeline", dest="pipeline", default='mgrast-prod', help="pipeline to view")
    parser.add_option("-s", "--summary", dest="summary", action="store_true", default=False, help="summarize by stage")
    
    (opts, args) = parser.parse_args()
    AWE_URL = opts.awe_url
     
    if opts.token and opts.clientgroup:
        clients = get_awe(AWE_URL+'/client?total=0&group='+opts.clientgroup, opts.token)
        stages = MGP[opts.pipeline]
        if opts.summary:
            pt = PrettyTable(["stage", "clients"])
            for i, s in enumerate(stages):
                num = 0
                for c in clients:
                    for k, v in c['current_work'].iteritems():
                        if v is True:
                            parts = k.split('_')
                            if int(parts[1]) == i:
                                num += 1
                pt.add_row([s, num])
        else:
            pt = PrettyTable(["name", "host", "status", "job", "stage"])
            sc = sorted(clients, key=itemgetter('name'))
            for c in sc:
                jobs = []
                work = []
                if c['Status'] == 'active-busy':
                    for k, v in c['current_work'].iteritems():
                        if v is True:
                            parts = k.split('_')
                            index = int(parts[1])
                            jobs.append(parts[0])
                            work.append(stages[index])
                    pt.add_row([c['name'], c['host'], c['Status'], "\n".join(jobs), "\n".join(work)])
                else:
                    pt.add_row([c['name'], c['host'], c['Status'], "", ""])
        pt.align = "l"
        print pt
    else:
        print "Missing required --token and --clientgroup"
        return 1
    return 0

if __name__ == "__main__":
    sys.exit( main(sys.argv) )

