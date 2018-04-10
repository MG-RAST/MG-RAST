#!/usr/bin/env python

import sys
import json
import urllib2
import argparse
from operator import itemgetter
from prettytable import PrettyTable

AWE_URL = 'https://awe.mg-rast.org'
MGP = {
    'mgrast-prod-4.0.3': [
        'qc_stats',
        'adapter trim',
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
        'dark matter extraction',
        'abundance cassandra load',
        'done stage',
        'notify job completion'
    ],
    'inbox_action': [
        'step 1',
        'step 2',
        'step 3'
    ],
    'submission': [
        'step 1'
    ],
    'mgrast-submit-ebi': [
        'step 1',
        'step 2'
    ]
}
CGS = [
    'mgrast_dbload',
    'mgrast_single',
    'mgrast_multi'
]

def max_pipeline():
    lens = map(lambda x: len(x), MGP.values())
    return max(lens)

def get_awe(url, token):
    header = {'Accept': 'application/json', 'Authorization': 'mgrast '+token}
    req = urllib2.Request(url, headers=header)
    res = urllib2.urlopen(req)
    obj = json.loads(res.read())
    return obj['data']

def client_status(c):
    if c['busy']:
        return 'busy'
    if c['online']:
        return 'online'
    if c['suspended']:
        return 'suspended'
    return 'unknown'

def job_error(e):
    if e['apperror']:
        parts = e['apperror'].split('\n')
        trim = filter(lambda x: x.find('ERR') != -1, parts)
        return "\n".join(trim)
    if e['worknotes']:
        return e['worknotes']
    if e['servernotes']:
        return e['servernotes']
    return 'unknown'

def main(args):
    global AWE_URL
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(title='subcommands', help='sub-command help', dest='commands')
    
    info_parser = subparsers.add_parser("info")
    
    client_parser = subparsers.add_parser("client")
    client_parser.add_argument("-a", "--awe_url", dest="awe_url", default=AWE_URL, help="AWE API url")
    client_parser.add_argument("-t", "--token", dest="token", default=None, help="User token")
    client_parser.add_argument("-c", "--clientgroup", dest="clientgroup", default=None, help="clientgroup to view")
    client_parser.add_argument("-p", "--pipeline", dest="pipeline", default='mgrast-prod-4.0.3', help="pipeline to view")
    
    pipeline_parser = subparsers.add_parser("pipeline")
    pipeline_parser.add_argument("-a", "--awe_url", dest="awe_url", default=AWE_URL, help="AWE API url")
    pipeline_parser.add_argument("-t", "--token", dest="token", default=None, help="User token")
    pipeline_parser.add_argument("-p", "--pipeline", dest="pipeline", default='mgrast-prod-4.0.3', help="pipeline to view")
    
    suspend_parser = subparsers.add_parser("suspend")
    suspend_parser.add_argument("-a", "--awe_url", dest="awe_url", default=AWE_URL, help="AWE API url")
    suspend_parser.add_argument("-t", "--token", dest="token", default=None, help="User token")
    suspend_parser.add_argument("-p", "--pipeline", dest="pipeline", default='mgrast-prod-4.0.3', help="pipeline to view")
    suspend_parser.add_argument("-s", "--stage", dest="stage", type=int, default=None, help="index of stage to view")
    
    try:
        args = parser.parse_args()
    except Exception as e:
        print "Error: %s"%(str(e))
        parser.print_help()
        return 1
    
    if not args.commands:
        print "No command provided"
        parser.print_help()
        return 1
    
    if args.commands == "info":
        ptp = PrettyTable()
        ptp.add_column('task #', range(max_pipeline()))
        for k, v in MGP.iteritems():
            ptp.add_column("pipeline: "+k, v)
        ptp.align = "l"
        print ptp
        ptc = PrettyTable()
        ptc.add_column("clientgroups", CGS)
        ptc.align = "l"
        print ptc
        return 0
    
    if not args.token:
        print "Missing required --token"
        parser.print_help()
        return 1
    
    AWE_URL = args.awe_url
    stages  = MGP[args.pipeline]
    
    if args.commands == "client":
        if args.clientgroup not in CGS:
            print "Invalid clientgroup"
            parser.print_help()
            return 1
        clients = get_awe(AWE_URL+'/client?group='+args.clientgroup, args.token)
        pt = PrettyTable(["name", "host", "status", "job", "stage"])
        seen = set()
        for i, s in enumerate(stages):
            for c in clients:
                if 'data' in c['current_work']:
                    for d in c['current_work']['data']:
                        parts = d.split('_')
                        if int(parts[1]) == i:
                            pt.add_row([c['name'], c['host_ip'], client_status(c), parts[0], s])
                            seen.add(c['name'])
        for c in clients:
            if c['name'] not in seen:
                pt.add_row([c['name'], c['host_ip'], client_status(c), "", ""])
        pt.align = "l"
        print pt
    
    if args.commands == "pipeline":
        clients = get_awe(AWE_URL+'/client', args.token)
        pt = PrettyTable(["task #", "stage name"]+CGS)
        for i, s in enumerate(stages):
            num = 0
            row = [i, s]+[0 for _ in range(len(CGS))]
            for c in clients:
                if (c['group'] in CGS) and ('data' in c['current_work']):
                    for d in c['current_work']['data']:
                        parts = d.split('_')
                        if int(parts[1]) == i:
                            row[CGS.index(c['group'])+2] += 1
            pt.add_row(row)
        pt.align = "l"
        print pt
    
    if args.commands == "suspend":
        jobs = get_awe("%s/job?query&state=suspend&info.pipeline=%s&limit=0"%(AWE_URL, args.pipeline), args.token)
        if args.stage == None:
            pt = PrettyTable(["task #", "stage name", "suspended"])
            for i, s in enumerate(stages):
                num = 0
                row = [i, s, 0]
                for j in jobs:
                    if j['error'] and j['error']['taskfailed']:
                        parts = j['error']['taskfailed'].split('_')
                        if int(parts[1]) == i:
                            row[2] += 1
                pt.add_row(row)
            pt.align = "l"
            print pt
        else:
            pt = PrettyTable(["id", "job name", "mg ID", "error"])
            for j in jobs:
                if j['error'] and j['error']['taskfailed']:
                    parts = j['error']['taskfailed'].split('_')
                    if int(parts[1]) == args.stage:
                        pt.add_row([j['id'], j['info']['name'], j['info']['userattr']['id'], job_error(j['error'])])
            pt.align = "l"
            print pt
    
    return 0

if __name__ == "__main__":
    sys.exit( main(sys.argv) )

