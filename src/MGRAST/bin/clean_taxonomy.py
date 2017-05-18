#!/usr/bin/env python

import os
import sys
import copy
import json
from optparse import OptionParser
from collections import defaultdict

"""
Requires 'id' and 'parentNodes' fields.
"""

ROOT_ID = None
RANK_PREFIX = 'super,sub,infra,parv,cohort,forma,tribe,varietas'

def toRemove(data):
    remove = []
    for n in data.itervalues():
        if (len(n['childNodes']) == 0) and ((not n['description']) or (n['description'] == n['label'])):
            remove.append(copy.deepcopy(n))
    return remove

def cleanDesc(nodes):
    i = 1
    remove = toRemove(nodes)
    while len(remove) > 0:
        print "round %d, remove %d"%(i, len(remove))
        for r in remove:
            if ROOT_ID and (r['id'] == ROOT_ID):
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
    print "round %d, remove %d"%(i, len(remove))
    return nodes

def checkRank(node, prefixes):
    if 'rank' not in node:
        return "missing"
    for pre in prefixes:
        if node['rank'].startswith(pre):
            return pre
    return None

def cleanRank(nodes, prefixes):
    removed = defaultdict(int)
    nodeIds = nodes.keys()
    for nid in nodeIds:
        if nid not in nodes:
            continue
        if ROOT_ID and (nid == ROOT_ID):
            continue
        n = nodes[nid]
        key = checkRank(n, prefixes)
        if not key:
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
        print "removed prefix: %s, %d nodes"%(r, removed[r])
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

def pruneTree(nodes, prune):
    for p in prune:
        i = 0
        if p not in nodes:
            continue
        decendents = getDescendents(nodes, p)
        toDelete = set(decendents)
        for d in toDelete:
            if d in nodes:
                i += 1
                del nodes[d]
        print "pruned %s, %d decendents removed"%(p, i)
    return nodes

def main(args):
    global ROOT_ID
    parser = OptionParser(usage="usage: %prog [options] -i <input file> -o <output file>")
    parser.add_option("-i", "--input", dest="input", default=None, help="input .json file")
    parser.add_option("-o", "--output", dest="output", default=None, help="output: .json file")
    parser.add_option("-n", "--nest", dest="nest", action="store_true", default=False, help="nodes dict is nested within 'nodes' field, default is not")
    parser.add_option("-d", "--desc", dest="desc", action="store_true", default=False, help="remove all nodes with no descrption, walk tree from leaf nodes up")
    parser.add_option("-r", "--rank", dest="rank", action="store_true", default=False, help="remove all nodes with rank prefix or no rank, connect childern to grandparents")
    parser.add_option("-p", "--prune", dest="prune", default=None, help="comma seperated list of ids, those ids and all their descendents will be removed from output")
    parser.add_option("", "--root", dest="root", default=None, help="root id of ontology, required if not using 'nest' option")
    parser.add_option("", "--prefix", dest="prefix", default=RANK_PREFIX, help="comma seperated list of rank prefixes, default is: "+RANK_PREFIX)
    parser.add_option("", "--no_id", dest="no_id", action="store_true", default=False, help="remove 'id' from struct to reduce size, only for --full")
    parser.add_option("", "--no_parents", dest="no_parents", action="store_true", default=False, help="remove 'parentNodes' from struct to reduce size")
    (opts, args) = parser.parse_args()
    if not (opts.input and os.path.isfile(opts.input)):
        parser.error("missing input")
    if not opts.output:
        parser.error("missing output")
    if opts.root:
        ROOT_ID = opts.root
    
    ontol = json.load(open(opts.input, 'r'))
    if opts.nest:
        nodes = ontol['nodes']
        ROOT_ID = ontol['rootNode']
    else:
        nodes = ontol
    
    # rank cleanup
    if opts.rank:
        prefixes = opts.prefix.split(",")
        nodes = cleanRank(nodes, prefixes)
    
    # description cleanup
    if opts.desc:
        nodes = cleanDesc(nodes)
    
    # prune branches
    if opts.prune:
        prune = opts.prune.split(',')
        nodes = pruneTree(nodes, prune)
    
    # trim if needed
    if opts.no_id:
        for v in nodes.itervalues():
            del v['id']
    if opts.no_parents:
        for v in nodes.itervalues():
            del v['parentNodes']
    
    # output
    if opts.nest:
        ontol['nodes'] = nodes
    else:
        ontol = nodes
    json.dump(ontol, open(opts.output, 'w'), separators=(',',':'))

if __name__ == "__main__":
    sys.exit(main(sys.argv))
