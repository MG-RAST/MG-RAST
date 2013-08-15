#!/usr/bin/env python

# This script calls the MG-RAST API and attempts to download the raw data file for a 
# metagenome whose MG-RAST ID is specified.

import sys, os, re
from optparse import OptionParser

def retrieveMGRbyaccession(accession):
    a = re.search(r"(.......\..)$", accession).group(1)
    if key == "":
        sys.stderr.write("Warning: MGR webkey not defined\n")
        s1 = "curl http://api.metagenomics.anl.gov/2/sequenceset/mgm%s-050-1/             > %s.gz"  % ( a, a ) 
    else: 
        sys.stderr.write("Using MGR webkey %s\n" % key)
        s1 = "curl 'http://api.metagenomics.anl.gov/2/sequenceset/mgm%s-050-1/?&auth=%s'  > %s.gz" % ( a, key, a )
#    print jsonobject
    sys.stderr.write("Executing %s\n" % s1) 
    os.popen(s1)
  
if __name__ == '__main__':
    usage  = '''usage: downloadMGR.py <accession number> 
example: downloadMGR.py  MGR4440613.3'''
    parser = OptionParser(usage)
    (opts, args) = parser.parse_args()
    try:
        key = os.environ["MGRKEY"]
    except KeyError:
        key = ""
  
    try :
        accession = args[0]
    except IndexError:
        parser.error("accession is a required parameter\n" )
  
    if re.search(r"^(\d\d\d\d\d\d\d\.\d)$", accession): 
        retrieveMGRbyaccession(accession)
    elif re.search(r"^(MGR\d\d\d\d\d\d\d.\d)$", accession): 
        retrieveMGRbyaccession(accession)
    else: 
        print "Don't recognize acecssion %s" % accession
        sys.exit()
