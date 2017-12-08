#!/usr/bin/env python

import os
import sys
import copy
import json
import argparse
from collections import defaultdict

"""
Requires 'id' and 'parentNodes' fields.
"""

RANK_PREFIX = 'super,sub,infra,parv,cohort,forma,tribe,varietas'

def toRemove(data):
    remove = []
    for n in data.itervalues():
        if (len(n['childNodes']) == 0) and ((not n['description']) or (n['description'] == n['label'])):
            remove.append(copy.deepcopy(n))
    return remove

def cleanDesc(nodes, root_id):
    i = 1
    remove = toRemove(nodes)
    while len(remove) > 0:
        print "round %d, remove %d"%(i, len(remove))
        for r in remove:
            if root_id and (r['id'] == root_id):
                continue
            # this node has no children
            # update parents children list
            for p in r['parentNodes']:
                if p in nodes:
                    nodes[p]['childNodes'].remove(r['id'])
            # remove node
            if r['id'] in nodes:
                del nodes[r['id']]
        remove = toRemove(nodes)
        i += 1
    print "root %s: round %d, remove %d"%(root_id, i, len(remove))
    return nodes

def checkRank(node, prefixes):
    if 'rank' not in node:
        return "missing"
    for pre in prefixes:
        if node['rank'].startswith(pre):
            return pre
    return None

def cleanRank(nodes, root_id, prefixes):
    removed = defaultdict(int)
    nodeIds = nodes.keys()
    for nid in nodeIds:
        if nid not in nodes:
            continue
        if root_id and (nid == root_id):
            continue
        n = nodes[nid]
        key = checkRank(n, prefixes)
        if not key:
            continue
        # special case of strain / species
        if (len(n['childNodes']) == 0) and (len(n['parentNodes']) == 1) and ('rank' in nodes[n['parentNodes'][0]]):
            if nodes[n['parentNodes'][0]]['rank'] == 'species':
                nodes[nid]['rank'] = 'strain'
                continue
            if nodes[n['parentNodes'][0]]['rank'] == 'genus':
                nodes[nid]['rank'] = 'species'
                continue
        # update child lists of parents
        for p in n['parentNodes']:
            if p in nodes:
                temp = list(set(nodes[p]['childNodes'] + n['childNodes']))
                temp.remove(nid)
                nodes[p]['childNodes'] = temp
        # update parent lists of children
        for c in n['childNodes']:
            if c in nodes:
                temp = list(set(nodes[c]['parentNodes'] + n['parentNodes']))
                temp.remove(nid)
                nodes[c]['parentNodes'] = temp
        # remove node
        del nodes[nid]
        removed[key] += 1
    for r in removed.keys():
        print "root %s: removed prefix: %s, %d nodes"%(root_id, r, removed[r])
    return nodes

def getDescendents(nodes, tid):
    decendents = []
    if tid in nodes:
        decendents = [tid]
        children = nodes[tid]['childNodes']
        if len(children) > 0:
            for child in children:
                decendents.extend(getDescendents(nodes, child))
    return decendents

def pruneTree(nodes, root_id, prune):
    pruneParents = set()
    for p in prune:
        i = 0
        if p not in nodes:
            continue
        for pn in nodes[p]['parentNodes']:
            pruneParents.add(pn)
        decendents = getDescendents(nodes, p)
        toDelete = set(decendents)
        for d in toDelete:
            if d in nodes:
                i += 1
                del nodes[d]
        print "root %s: pruned %s, %d decendents removed"%(root_id, p, i)
    for pp in pruneParents:
        if pp not in nodes:
            continue
        for p in prune:
            if p in nodes[pp]['childNodes']:
                nodes[pp]['childNodes'].remove(p)
    return nodes

def main(args):
    parser = argparse.ArgumentParser(usage="usage: %prog [options] -i <input file> -o <output file>")
    parser.add_argument("-i", "--input", dest="input", default=[], help="one or more input .json file", action='append')
    parser.add_argument("-o", "--output", dest="output", default=None, help="output: .json file")
    parser.add_argument("-d", "--desc", dest="desc", action="store_true", default=False, help="remove all nodes with no descrption, walk tree from leaf nodes up")
    parser.add_argument("-r", "--rank", dest="rank", action="store_true", default=False, help="remove all nodes with rank prefix or no rank, connect childern to grandparents")
    parser.add_argument("-p", "--prune", dest="prune", default=None, help="comma seperated list of ids, those ids and all their descendents will be removed from output")
    parser.add_argument("--root", dest="root", default=None, help="id of root node to be created if mutiple inputs used")
    parser.add_argument("--prefix", dest="prefix", default=RANK_PREFIX, help="comma seperated list of rank prefixes, default is: "+RANK_PREFIX)
    parser.add_argument("--no_id", dest="no_id", action="store_true", default=False, help="remove 'id' from struct to reduce size, only for --full")
    parser.add_argument("--no_parents", dest="no_parents", action="store_true", default=False, help="remove 'parentNodes' from struct to reduce size")
    args = parser.parse_args()
    
    if len(args.input) == 0:
        parser.error("missing input")
    if (len(args.input) > 1) and (not args.root):
        parser.error("missing root id")
    if not args.output:
        parser.error("missing output")
    
    nodes = []
    for i in args.input:
        try:
            data = json.load(open(i, 'r'))
            root = data['rootNode']
            nodes.append(data)
        except:
            parser.error("input %s is invalid format"%(i))
    
    # remove messy branches
    # 'unclassified'
    # 'environmental samples'
    prune = []
    for node in nodes:
        for v in node['nodes'].itervalues():
            if v['label'].startswith('unclassified') or v['label'].startswith('environmental'):
                prune.append(v['id'])
    
    # add inputted
    if args.prune:
        prune.extend(args.prune.split(','))
    
    # prune branches
    for i, n in enumerate(nodes):
        nodes[i]['nodes'] = pruneTree(n['nodes'], n['rootNode'], prune)
    
    # rank cleanup
    if args.rank:
        prefixes = args.prefix.split(",")
        for i, n in enumerate(nodes):
            nodes[i]['nodes'] = cleanRank(n['nodes'], n['rootNode'], prefixes)
    
    # description cleanup
    if args.desc:
        for i, n in enumerate(nodes):
            nodes[i]['nodes'] = cleanDesc(n['nodes'], n['rootNode'])
    
    # trim if needed
    if args.no_id:
        for n in nodes:
            for v in n['nodes'].itervalues():
                del v['id']
    if args.no_parents:
        for n in nodes:
            for v in n['nodes'].itervalues():
                del v['parentNodes']
    
    # merge
    data = {}
    if len(nodes) > 1:
        data[args.root] = {
            'id': args.root,
            'label': 'root',
            'parentNodes': [],
            'childNodes': []
        }
        for n in nodes:
            data.update(n['nodes'])
            data[args.root]['childNodes'].append(n['rootNode'])
            data[n['rootNode']]['parentNodes'] = [args.root]
    else:
        data = n['nodes']
    
    # output
    json.dump(data, open(args.output, 'w'), separators=(',',':'))

if __name__ == "__main__":
    sys.exit(main(sys.argv))
