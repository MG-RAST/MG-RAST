#!/usr/bin/env python3

import argparse
import datetime
import glob
import importlib
import json
import logging
import os
import pymongo
import random
import re
import requests
import subprocess 

import sys
import time
import yaml

from uuid import getnode as get_mac
from subprocess import Popen, PIPE
from bson import json_util 

parser = argparse.ArgumentParser()

parser.add_argument("action" ,
                    choices=['update' , 'load' , 'drop' , 'list' , 'test'] ,
                    type=str ,
                    default=None
                    )
parser.add_argument("--host",
                    type=str, dest="host",
                    default="localhost:27017" ,
                    help="mongo host and port")
parser.add_argument("--db",
                    type=str, dest='db',
                    default=None ,
                    help="database name")
parser.add_argument("--collection",
                    type=str, dest='collection',
                    default=None ,
                    help="collection name")                    
parser.add_argument("--user",
                    type=str,
                    help="user" ,
                    default=None)
parser.add_argument("--password",
                    type=str ,
                    default=None )
parser.add_argument("--token",
                    type=str ,
                    help="user token with prefix, e.g. mgrast 1234" ,
                    default=None )                    
parser.add_argument("--debug",
                    action="store_true" ,
                    default=False )
parser.add_argument("--dry-run",
                    action="store_true" ,
                    default=False )   
parser.add_argument("--force",
                    action="store_true" ,
                    default=False ,
                    help="force update" )                    





# mutually exclusive 
json_document_input = parser.add_mutually_exclusive_group()    
json_document_input.add_argument("--json",
                    type=str ,
                    help='json string' ,
                    default=None )   
json_document_input.add_argument("--json-file",
                    type=argparse.FileType('r') ,
                    help='json document' ,
                    )   

                                        
 

def load_document(db , collection , data) :
  if not args.dry_run :
    print("Creating collection and adding data")
    db = client[args.db]
    col =db[collection]
    col.insert_one(data)
  else:
    print("Dry run, not loaded data")
    
  sys.exit() 


def update_token( db , collection , query , token ) :
  
  if not query :
    print("Please provide jason string for query (--json or --json-file")
    sys.exit()

  if not token : 
    print("Provide data token (--token 'PREFIX TOKEN' ")
    sys.exit()

  if not collection in db.list_collection_names() :
    print('Can not find find collection ' + collection + " in " + args.db )


  print("Updating datatoken in " + collection +  "(" + args.db + ")" )
  col = db[collection]

  # find documents

  count = col.count_documents( query )
  if  not  count == 1 :
    print("Too many documents (" + str(count) + "), please specify query to return single job document")
    if not args.force:
      print("No force, aborting")
      sys.exit(1)

  results = col.find( query ) 
  print(results)
  #  test if worklfow document
  # job = results[0]

  # update token
  for d in results :
    print(d['_id'])
    for task in d['tasks'] :
   
      for i in task['inputs'] : 
        old = i['datatoken'] if 'datatoken' in i else ""
        print( task['taskid'] + "\tinputs:\t" + old +"\t" + token)
      for i in task['outputs'] : 
        old = i['datatoken'] if 'datatoken' in i else ""
        print( task['taskid'] + "\toutputs:\t" + old +"\t" + token)    
  
    if not args.dry_run :
      print("Updating " + str(d['_id'] ) )
      f =  open( str(d['_id']) + "." + str(time.time()) + ".json"  , "w") 
      json.dump(json_util.dumps(d) , f)
      f.close()

      col.update_one( { '_id' : d['_id'] } , { "$set" : { "tasks.$[].inputs.$[].datatoken" : token }})
      # here - then folker has totally new concept
      col.update_one( { '_id' : d['_id'] } , { "$set" : { "tasks.$[].outputs.$[].datatoken" : token }}) 
      

  sys.exit(0)
  






### main ###



# test json
dataString=None

data = None # json.loads(dataString)




# set command line arguments
args = parser.parse_args()

debug       = args.debug
db          = args.db
collection  = args.collection
token       = args.token 
action      = args.action
force       = False


client = pymongo.MongoClient("mongodb://" + args.host )
dblist = client.list_database_names()


# load json
if args.json :
  data = json.loads( args.json )
if args.json_file :
  data = json.load( args.json_file)  

if args.db and args.db in dblist:  
  db = client[args.db]

else:
  print("The database does not exists.")
  print( dblist )
  if not action=="load" :
      sys.exit(0)


if action=="list" :
  print( db.list_collection_names() )
  sys.exit()

if action=="drop" :
  print("Dropping: " + args.db )
  if not args.dry_run:
    print( client.drop_database(args.db))
    pass
  sys.exit()


if action=="load" :
  if data :
    load_document(db,collection,data)
  else :
    print("Can not load into " + args.db + ", missing data")
    sys.exit()  
    
if action=="update" :
  if token :
    # use json from input for query
    query = data if data else  None  
    update_token(db , collection , query , token)

