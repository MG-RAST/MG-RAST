#!/usr/bin/env python

import os, sys, re, hashlib
from optparse import OptionParser
from multiprocessing import Pool
from Bio import SeqIO
from Bio.Seq import Seq
from Bio.SeqRecord import SeqRecord
from Bio.Alphabet import IUPAC

__doc__ = """
Script to take a repository file from the following formats:
   genbank, kegg, swiss, fasta
and output the following tab seperated files:

SOURCE.md52id2func:
   md5, id, function, organism, source, beg_pos*, end_pos*, strand*, contig_id*, contig_desc*, contig_length*
SOURCE.ms52id2ont:
   md5, id, function, ontology, source
SOURCE.md52seq:
   md5, sequence
SOURCE.id2xref:
   id, external refrence 1, [external refrence 2, external refrence 3, ...]
SOURCE.id2tax:
   id, genbank tax string

Values with * are optional, only genbank files contain that data."""

class Info:
    def __init__(self):
        self.source  = ''
        self.format  = 'fasta'
        self.verbose = False
        self.outdir  = ''
        self.orghead = False
        self.getont  = False
        self.getctg  = False
        self.gettax  = False
        self.amap    = {}

desc_re  = re.compile('(Rec|Sub)Name: Full=(.*?);')
entry_re = re.compile('^ENTRY\s+(\S+)\s+CDS\s+(.*)$', re.MULTILINE)
name_re  = re.compile('^NAME\s+(.*)$', re.MULTILINE)
func_re  = re.compile('^DEFINITION\s+(.*?)^\S', re.DOTALL | re.MULTILINE)
orth_re  = re.compile('^ORTHOLOGY\s+(.*?)^\S', re.DOTALL | re.MULTILINE)
dbref_re = re.compile('^DBLINKS\s+(.*?)^\S', re.DOTALL | re.MULTILINE)
seq_re   = re.compile('^AASEQ\s+\d+\s+(.*?)^\S', re.DOTALL | re.MULTILINE)
up_go_re = re.compile('^GO:GO:(.*)')
gb_go_re = re.compile('^GO:(\d+)\s+-\s+(.*)')
gb_go_rm = re.compile('( \[Evidence [A-Z]+\])')
ko_re    = re.compile('^(K\d+)\s+(.*)')
ogid_re  = re.compile('^(\S+?OG)\d+')
nr_re    = re.compile('^gi\|(\d+)\|(\w+)\|(\S+)\|\S*?\s+(.*)\]$')
nr_types = {'ref': 'RefSeq', 'gb': 'GenBank', 'emb': 'EMBL', 'dbj': 'DDBJ', 'pir': 'PIR', 'prf': 'PRF', 'pdb': 'PDB'}
go_types = ['GO_function', 'GO_process', 'GO_component']
file_ext = [".md52id2func", ".md52id2ont", ".md52seq", ".id2xref", ".id2tax"]
params   = Info()

def parse_nr_header(line):
    items = []
    hdr_set = nr_re.match(line)
    if hdr_set:
        (gi_id, nrdb, nrdb_id, func_org) = hdr_set.groups()
        if nrdb in params.amap:
            org_rev = ''
            rev_fo  = reverse_string(func_org)
            end_brk = 1
            beg_brk = 0
            for i, c in enumerate(rev_fo):
                if c == ']': end_brk += 1
                if c == '[': beg_brk += 1
                if beg_brk == end_brk: break
                org_rev += c
            org_txt  = reverse_string( org_rev )
            func_txt = reverse_string( rev_fo[i+1:] )
            items = [ gi_id, params.amap[nrdb], nrdb_id, func_txt.strip(), org_txt.strip() ]
    return items

def reverse_string(string):
    return string[::-1]

def get_eggnog_map(filename):
    emap = {}
    if filename is None:
        return emap
    if params.verbose: sys.stdout.write("Parsing file %s ... " %filename)
    fhdl = open(filename, 'r')
    try:
        for line in fhdl:
            if line.startswith("#"): continue
            parts = line.strip().split("\t")
            if parts[0] in emap:
                emap[ parts[0] ].append( [parts[3], parts[4]] )
            else :
                emap[ parts[0] ] = [ [parts[3], parts[4]] ]
    finally:
        fhdl.close()
    if params.verbose: sys.stdout.write("Done\n")
    return emap

def get_kegg_map(filename):
    kmap = {}
    if filename is None:
        return kmap
    if params.verbose: sys.stdout.write("Parsing file %s ... " %filename)
    for text in kegg_iter(filename):
        rec = get_kegg_rec(text)
        if (not rec.name) or (not rec.description): continue
        names = rec.name.split(', ')
        if len(names) > 1:
            kmap[ names[1] ] = [ rec.description, names[0] ]
    if params.verbose: sys.stdout.write("Done\n")
    return kmap

def kegg_iter(filename):
    fhdl = file(filename, 'rb')
    recs = ['']
    for data in iter(lambda: fhdl.read(100000), ''):
        recs = (recs[-1] + data).split("\n///\n")
        for rec in recs[:-1]:
            yield rec

def get_kegg_rec(text):
    record  = SeqRecord(Seq("",IUPAC.protein), id='', name='', description='', dbxrefs=[], annotations={'organism':''})
    entry_s = entry_re.search(text)
    name_s  = name_re.search(text)
    func_s  = func_re.search(text)
    orth_s  = orth_re.search(text)
    dbref_s = dbref_re.search(text)
    seq_s   = seq_re.search(text)
    if entry_s:
        record.id = entry_s.group(1)
        record.annotations['organism'] = entry_s.group(2).strip()
    if name_s:
        record.name = name_s.group(1).strip()
    if func_s:
        record.description = re.sub('\s+', ' ', func_s.group(1).strip())
    if orth_s:
        orths = {}
        for o in filter( lambda y: y, map(lambda x: ko_re.search(x.strip()), orth_s.group(1).strip().split("\n")) ):
            orths[ o.group(1) ] = o.group(2)
        record.annotations['orthology'] = orths
    if dbref_s:
        parts = dbref_s.group(1).split()
        if (len(parts) % 2) == 0:
            for i in range(0, len(parts)-1, 2):
                record.dbxrefs.append(parts[i].replace('NCBI-', '') + parts[i+1])
    if seq_s:
        record.seq = Seq( re.sub('\s+', '', seq_s.group(1)), IUPAC.protein )
    return record

def format_factory(out_files):
    (prot_f, ont_f, seq_f, ref_f, tax_f) = out_files
    source   = params.source
    form     = params.format
    org_desc = params.orghead
    get_ont  = params.getont
    get_ctg  = params.getctg
    get_tax  = params.gettax
    amap     = params.amap
    if form == 'genbank':    
        def parse_genbank(rec):
            if (not rec) or (not rec.id) or (not rec.seq): return
            cid   = rec.id
            cdesc = rec.description.rstrip('.')
            seq   = str(rec.seq).upper()
            clen  = len(seq)
            org   = rec.annotations['organism']
            # only one entry on rec (first feat is source and is not a feature), use first real feature, no contig data
            if len(rec.features) == 2:
                md5  = hashlib.md5(seq).hexdigest()
                func = ''
                if 'product' in rec.features[1].qualifiers:
                    func = rec.features[1].qualifiers['product'][0]
                seq_f.write("%s\t%s\n" %(md5, seq))
                prot_f.write("\t".join([md5, rec.name, func, org, source]) + "\n")
                if get_tax and ('taxonomy' in rec.annotations):
                    if rec.annotations['taxonomy'][0] == 'Root':
                        x = rec.annotations['taxonomy'].pop(0)
                    tax_f.write("%s\t%s;%s\n" %(rec.name, ";".join(rec.annotations['taxonomy']), org))
                return
            # multiple entries on rec, use CDS features, get contig data
            for feat in rec.features:
                if feat.type == 'CDS':
                    if ( (not feat.qualifiers) or (not feat.location) or
                         ('translation' not in feat.qualifiers) or
                         ('product' not in feat.qualifiers) ): continue
                    fid = ''
                    if 'protein_id' in feat.qualifiers:
                        fid = feat.qualifiers['protein_id'][0]
                    elif 'locus_tag' in feat.qualifiers:
                        fid = feat.qualifiers['locus_tag'][0]
                    else:
                        continue
                    seq  = feat.qualifiers['translation'][0]
                    md5  = hashlib.md5(seq).hexdigest()
                    func = feat.qualifiers['product'][0]
                    beg  = feat.location.start.position
                    end  = feat.location.end.position
                    if feat.strand:
                        strd = feat.strand
                    else:
                        strd = 1
                        if (beg > end):
                            strd = -1
                            beg  = feat.location.end.position
                            end  = feat.location.start.position
                    # output GO ontology
                    if get_ont:
                        for gtype in go_types:
                            if gtype in feat.qualifiers:
                                for goid in feat.qualifiers[gtype]:
                                    go_m = gb_go_re.match(goid)
                                    if go_m:
                                        desc = gb_go_rm.sub('', go_m.group(2))
                                        ont_f.write("\t".join([md5, go_m.group(1), desc, 'GO']) + "\n")
                    seq_f.write("%s\t%s\n" %(md5, seq))
                    if get_ctg:
                        prot_f.write("\t".join([md5, fid, func, org, source, str(beg), str(end), str(strd), cid, cdesc, str(clen)]) + "\n")
                    else:
                        prot_f.write("\t".join([md5, fid, func, org, source]) + "\n")
                    if ('db_xref' in feat.qualifiers) and (len(feat.qualifiers['db_xref']) > 0):
                        ref_f.write(fid + "\t" + "\t".join(feat.qualifiers['db_xref']) + "\n")
        return parse_genbank
    
    elif form == 'swiss':
        def parse_swiss(rec):
            if (not rec) or (not rec.id) or (not rec.seq): return
            seq  = str(rec.seq).upper()
            md5  = hashlib.md5(seq).hexdigest()
            func = rec.description
            srch = desc_re.search(func)
            if srch: func = srch.group(2)
            seq_f.write("%s\t%s\n" %(md5, seq))
            prot_f.write("\t".join([md5, rec.id, func, rec.annotations['organism'], source]) + "\n")
            if len(rec.dbxrefs) > 0:
                ref_str = rec.id
                for ref in rec.dbxrefs:
                    go_m = up_go_re.match(ref)
                    # output GO ontology
                    if go_m and get_ont:
                        ont_f.write("\t".join([md5, go_m.group(1), func, 'GO']) + "\n")
                    else:
                        ref_str += "\t" + ref
                ref_f.write(ref_str + "\n")
        return parse_swiss
    
    elif form == 'fasta':
        def parse_fasta(rec):
            if (not rec) or (not rec.id) or (not rec.seq): return
            desc = ''
            org  = ''
            func = ''
            hdrs = rec.description.split()
            seq  = str(rec.seq).upper()
            md5  = hashlib.md5(seq).hexdigest()
            seq_f.write("%s\t%s\n" %(md5, seq))
            if len(hdrs) > 1:
                hdrs.pop(0)
                desc = " ".join(hdrs)
                if desc.startswith("("): desc = desc.strip(')(')
                if desc.startswith("|"): desc = desc.strip('| ')
            if org_desc: org  = desc
            else:        func = desc
            if get_ont and (rec.id in amap):
                for f in amap[rec.id]:
                    prot_f.write("\t".join([md5, rec.id, f[1], org, source]) + "\n")
                    ogid_m = ogid_re.match(f[0])
                    if ogid_m:
                        ont_f.write("\t".join([md5, f[0], f[1], ogid_m.group(1)]) + "\n")
            else:
                prot_f.write("\t".join([md5, rec.id, func, org, source]) + "\n")
        return parse_fasta

    elif form == 'nr':
        def parse_nr(rec):
            if (not rec) or (not rec.description) or (not rec.seq): return
            get_seq = False
            hdrs = rec.description.split('\x01')
            seq  = str(rec.seq).upper()
            md5  = hashlib.md5(seq).hexdigest()
            if len(hdrs) > 0:
                for h in hdrs:
                    info = parse_nr_header(h)
                    if len(info) > 0:
                        (gi_id, nrdb, nrdb_id, func, org) = info
                        get_seq = True
                        prot_f.write("\t".join([md5, nrdb_id, func, org, nrdb]) + "\n")
                        ref_f.write("%s\tGI:%s\n"%(nrdb_id, gi_id))
                if get_seq:
                    seq_f.write("%s\t%s\n" %(md5, seq))
        return parse_nr

    elif form == 'kegg':
        def parse_kegg(text):
            rec = get_kegg_rec(text)
            if (not rec.id) or (not rec.description) or (not rec.seq): return
            seq  = str(rec.seq).upper()
            md5  = hashlib.md5(seq).hexdigest()
            org  = rec.annotations['organism']
            code = ""
            orth = []
            if org in amap:
                (org, code) = amap[org]
                code += ":"
            # output KO ontology
            if get_ont and ('orthology' in rec.annotations):
                orth = rec.annotations['orthology']
                for oid, odesc in orth.iteritems():
                    ont_f.write("\t".join([md5, oid, odesc, 'KO']) + "\n")
            seq_f.write("%s\t%s\n" %(md5, seq))
            prot_f.write("\t".join([md5, code + rec.id, rec.description, org, source]) + "\n")
            if len(rec.dbxrefs) > 0:
                ref_f.write(rec.id + "\t" + "\t".join(rec.dbxrefs) + "\n")
        return parse_kegg

    else:
        return None

def process_file(infile):
    o_files = []
    o_hdls  = []
    fformat = params.format
    fname   = os.path.basename(infile)
    for e in file_ext: o_files.append( os.path.join(params.outdir, fname + e) )
    for f in o_files:  o_hdls.append( open(f, 'w') )

    parse_format = format_factory( o_hdls )
    if not parse_format:
        sys.stderr.write("Invalid format %s\n"%fformat)
        sys.exit(1)
    
    if params.verbose: sys.stdout.write("Parsing file %s ...\n" %infile)
    if fformat == 'kegg':
        for rec in kegg_iter(infile):
            parse_format(rec)
    else:
        if fformat == 'nr': fformat = 'fasta'
        for rec in SeqIO.parse(infile, fformat):
            parse_format(rec)

    for h in o_hdls: h.close()
    return os.path.join(params.outdir, fname)
    

usage = "usage: %prog [options] source input_file1 [input_file2 input_file3 ...]" + __doc__

def main(args):
    global params
    parser = OptionParser(usage=usage)
    parser.add_option("-f", "--format", dest="format", metavar="FORMAT", default="fasta",
                      help="FORMAT inputed file is in. Must be one of following: genbank, kegg, swiss, nr, fasta [default is 'fasta']")
    parser.add_option("-n", "--nr_dbs", dest="nrdbs", metavar="DBs", default="ref,gb",
                      help="Comma seperated list of databases to parse out of ncbi nr, from following: ref, gb, emb, dbj, pir, prf, pdb [default is 'ref,gb']")
    parser.add_option("-p", "--processes", dest="processes", metavar="NUM_PROCESSES", type="int", default=4, help="Number of processes to use [default '4']")
    parser.add_option("-k", "--kegg_map", dest="keggmap", metavar="FILE", default=None, help="Optional KEGG genome FILE for org name mapping")
    parser.add_option("-e", "--eggnog_map", dest="eggnogmap", metavar="FILE", default=None, help="Optional eggNOG orthgroups tabed FILE for func mapping")
    parser.add_option("-d", "--out_dir", dest="outdir", metavar="DIR", default="", help="DIR to write output [default is current dir]")
    parser.add_option("-o", "--org_header", dest="orgheader", action="store_true", default=False, help="For fasta files, header description is organism [default is function]")
    parser.add_option("-g", "--get_ontology", dest="getont", action="store_true", default=False, help="Output ontology (id, type) for proteins with mapped ontology [default is off]")
    parser.add_option("-c", "--get_contig", dest="getcontig", action="store_true", default=False, help="Output contig info for organism genbank files [default is off]")
    parser.add_option("-t", "--get_tax", dest="gettax", action="store_true", default=False, help="Output taxonomy string for genbank files [default is off]")
    parser.add_option("-v", "--verbose", dest="verbose", action="store_true", default=False, help="Wordy [default is off]")
    
    (opts, args) = parser.parse_args()
    if len(args) < 2:
        parser.error("Incorrect number of arguments")
    sfiles = filter(lambda x: os.path.isfile(x), args[1:])
    scount = len(sfiles)

    params.source  = args[0]
    params.format  = opts.format
    params.verbose = opts.verbose
    params.outdir  = opts.outdir
    params.orghead = opts.orgheader
    params.getont  = opts.getont
    params.getctg  = opts.getcontig
    params.gettax  = opts.gettax
    
    if (params.format == 'nr') and opts.nrdbs:
        for d in opts.nrdbs.split(','):
            if d in nr_types:
                params.amap[d] = nr_types[d]
    elif (params.format == 'kegg') and opts.keggmap and os.path.isfile(opts.keggmap):
        params.amap = get_kegg_map(opts.keggmap)
    elif (params.format == 'fasta') and opts.eggnogmap and os.path.isfile(opts.eggnogmap):
        params.amap = get_eggnog_map(opts.eggnogmap)

    if scount < opts.processes:
        min_proc = scount
    else:
        min_proc = opts.processes

    if min_proc == 1:
        if params.verbose: sys.stdout.write("Parsing %d %s files, single threaded\n"%(scount, params.format))
        rfiles = []
        for f in sfiles:
            r = process_file(f)
            rfiles.append(r)
    else:
        if params.verbose: sys.stdout.write("Parsing %d %s files using %d threades\n"%(scount, params.format, min_proc))
        pool   = Pool(processes=min_proc)
        rfiles = pool.map(process_file, sfiles, 1)
        pool.close()
        pool.join()
    if params.verbose: sys.stdout.write("Done\n")

    if params.verbose: sys.stdout.write("Merging %d files ... "%len(rfiles))
    for e in file_ext:
        out_file = os.path.join(params.outdir, params.source + e)
        file_set = map( lambda x: x + e, rfiles )
        if os.path.isfile(out_file):
            os.remove(out_file)
        os.system( "cat %s | sort -u > %s"%(" ".join(file_set), out_file) )
        for f in file_set:
            os.remove(f)
        if os.path.isfile(out_file) and (os.path.getsize(out_file) == 0):
            os.remove(out_file)
    if params.verbose: sys.stdout.write("Done\n")

    if params.verbose: sys.stdout.write("All Done\n")

if __name__ == "__main__":
    sys.exit( main(sys.argv) )
