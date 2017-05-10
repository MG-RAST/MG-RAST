#!/usr/bin/env python

import os
import re
import sys
import json
from optparse import OptionParser
from collections import defaultdict

# declare a blank dictionary, keys are the term_ids
terms = {}
quote = re.compile(r'\"(.+?)\"')
term  = re.compile(r'^[A-Z]+:\d+$')
# to check for circular recursion
ascSeen  = set()
descSeen = set()
# max recrusion depth
sys.setrecursionlimit(10000)

def getTerm(stream):
    block = []
    for line in stream:
        if line.strip() == "[Term]" or line.strip() == "[Typedef]":
            break
        else:
            if line.strip() != "":
                block.append(line.strip())
    return block

def parseTagValue(term):
    data = defaultdict(list)
    for line in term:
        tag = line.split(': ',1)[0]
        value = line.split(': ',1)[1]
        qval  = quote.match(value)
        if tag == 'relationship':
            tag = value.split(' ', 1)[0]
            value = value.split(' ', 1)[1]
        if qval:
            value = qval.group(1)
        data[tag].append(value)
    return data

def getDescendents(tid, full=False):
    decendents = {} if full else []
    if terms.has_key(tid):
        if tid in descSeen:
            # avoid circular refrences
            return decendents if full else list(set(decendents))
        descSeen.add(tid)
        decendents = {tid: terms[tid]} if full else [(terms[tid]['label'], tid)]
        children = terms[tid]['childNodes']
        if len(children) > 0:
            for child in children:
                if full:
                    decendents.update(getDescendents(child, full=full))
                else:
                    decendents.extend(getDescendents(child, full=full))
    return decendents if full else list(set(decendents))

def getAncestors(tid, full=False):
    ancestors = {} if full else []
    if terms.has_key(tid):
        if tid in ascSeen:
            # avoid circular refrences
            return ancestors if full else list(set(ancestors))
        ascSeen.add(tid)
        ancestors = {tid: terms[tid]} if full else [(terms[tid]['label'], tid)]
        parents = terms[tid]['parentNodes']
        if len(parents) > 0:
            for parent in parents:
                if full:
                    ancestors.update(getAncestors(parent, full=full))
                else:
                    ancestors.extend(getAncestors(parent, full=full))
    return ancestors if full else list(set(ancestors))

def getChildren(tid, full=False):
    children = {} if full else []
    if terms.has_key(tid):
        for c in terms[tid]['childNodes']:
            if full:
                children[c] = terms[c]
            else:
                children.append((terms[c]['label'], c))
    return children if full else list(set(children))

def getParents(tid, full=False):
    parents = {} if full else []
    if terms.has_key(tid):
        for p in terms[tid]['parentNodes']:
            if full:
                parents[p] = terms[p]
            else:
                parents.append((terms[p]['label'], p))
    return parents if full else list(set(parents))

def getTop(full=False):
    top = {} if full else []
    for t, info in terms.iteritems():
        if (len(info['parentNodes']) == 0) and (len(info['childNodes']) > 0) and term.match(t):
            if full:
                top[t] = terms[t]
            else:
                top.append((terms[t]['label'], t))
    return top if full else list(set(top))

def outputJson(data, ofile):
    if ofile:
        json.dump(data, open(ofile, 'w'))
    else:
        print json.dumps(data, sort_keys=True, indent=4)

def outputTab(data, ofile):
    out_str = "\n".join(map(lambda x: "\t".join(x), data))
    if ofile:
        open(ofile, 'w').write(out_str+"\n")
    else:
        print out_str

def main(args):
    global terms
    parser = OptionParser(usage="usage: %prog [options] -i <input file> -o <output file>")
    parser.add_option("-i", "--input", dest="input", default=None, help="input .obo file")
    parser.add_option("-o", "--output", dest="output", default=None, help="output: .json file or stdout, default is stdout")
    parser.add_option("-g", "--get", dest="get", default='all', help="output to get: all, top, ancestors, parents, children, descendents. 'all' if no term_id")
    parser.add_option("-f", "--full", dest="full", action="store_true", default=False, help="return output as struct with relationships, default is list of tuples (name, id)")
    parser.add_option("-t", "--term_id", dest="term_id", default=None, help="term id if doing relationship lookup")
    parser.add_option("-r", "--relations", dest="relations", default='is_a,part_of,located_in', help="comma seperated list of relations to use, default is 'is_a,part_of,located_in'")
    parser.add_option("-m", "--metadata", dest="metadata", default=None, help="add the given JSON data as top level metadata info to return struct, only usable with --full option")
    parser.add_option("", "--tab", dest="tab", action="store_true", default=False, help="return output as tabbed list instead of json, only for not --full")
    (opts, args) = parser.parse_args()
    if not (opts.input and os.path.isfile(opts.input)):
        parser.error("missing input")
    if not opts.relations:
        parser.error("missing relations")
    if (not opts.term_id) and (opts.get != 'top'):
        opts.get = 'all'
    
    oboFile = open(opts.input, 'r')
    relations = opts.relations.split(',')
    
    # skip the file header lines
    getTerm(oboFile)

    # infinite loop to go through the obo file.
    # breaks when the term returned is empty, indicating end of file
    while 1:
        # get the term using the two parsing functions
        term = parseTagValue(getTerm(oboFile))
        if len(term) != 0:
            termID = term['id'][0]
            termName = term['name'][0]
            termDesc = term['def'][0] if 'def' in term else term['name'][0]
            
            # only add to the structure if the term has a relation tag
            # the relation value contains ID and term definition, we only want ID
            termParents = []
            for rel in relations:
                if term.has_key(rel):
                    termParents.extend([p.split()[0] for p in term[rel]])
        
            # each ID will have two arrays of parents and children
            if not terms.has_key(termID):
                terms[termID] = {'parentNodes':[], 'childNodes':[]}
            terms[termID]['id'] = termID
            terms[termID]['label'] = termName
            terms[termID]['description'] = termDesc
            
            # append parents of the current term
            terms[termID]['parentNodes'] = termParents
            
            # for every parent term, add this current term as children
            for termParent in termParents:
                if not terms.has_key(termParent):
                    terms[termParent] = {'parentNodes':[], 'childNodes':[]}
                terms[termParent]['childNodes'].append(termID)
        else:
            break
    
    # output
    data = None
    if opts.get == 'top':
        data = getTop(full=opts.full)
    elif opts.get == 'ancestors':
        data = getAncestors(opts.term_id, full=opts.full)
    elif opts.get == 'parents':
        data = getParents(opts.term_id, full=opts.full)
    elif opts.get == 'children':
        data = getChildren(opts.term_id, full=opts.full)
    elif opts.get == 'descendents':
        data = getDescendents(opts.term_id, full=opts.full)
    elif opts.full:
        data = terms
    else:
        data = [(terms[k]['label'], k) for k in sorted(terms)]
    
    # have global info
    if opts.full and opts.metadata:
        try:
            mdata = json.loads(opts.metadata)
            mdata['nodes'] = data
            outputJson(mdata, opts.output)
        except:
            outputJson(data, opts.output)
    # tabbed list output
    elif opts.tab and (not opts.full):
        outputTab(data, opts.output)
    # just dump as is
    else:
        outputJson(data, opts.output)

if __name__ == "__main__":
    sys.exit(main(sys.argv))
