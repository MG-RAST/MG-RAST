#!/bin/bash

HELP=0
LOAD=''
DEPLOY='/scratch'
VACH='1'
MKEY='_ach'
MHOST='localhost:11211'
TYPES=( 'source' 'organism' 'function' 'ontology' 'md5_lca' 'md5_protein' 'md5_rna' 'md5_ontology' 'md5' )

# get args
while getopts hv:l:d:v:k:m: option; do
    case "${option}"
	    in
	    h) HELP=1;;
	    l) LOAD=${OPTARG};;
	    d) DEPLOY=${OPTARG};;
	    v) VACH=${OPTARG};;
	    k) MKEY=${OPTARG};;
	    m) MHOST=${OPTARG};;
    esac
done

# help
if [ $HELP -eq 1 ]; then
    echo "Usage: load_memcache.sh [-h] -l <load script: $LOAD> -d <deploy dir: $DEPLOY> -v <ach version: $VACH> -k <memcache key: $MKEY> -m <memcache host: $MHOST>"
    exit
fi

sudo mkdir $DEPLOY
sudo chown ${USER}:${USER} $DEPLOY

for T in "${TYPES[@]}"; do
    echo `date`
    echo "downloading $T ..."
    wget -q -O ${DEPLOY}/${T}_map.gz ftp://ftp.mg-rast.org/data/MD5nr/memcached/v${VACH}/${T}_map.gz
    echo "gunzipping $T ..."
    gunzip -v ${DEPLOY}/${T}_map.gz
    echo "loading $T ..."
    $LOAD --verbose --mem_host $MHOST --mem_key $MKEY --map ${DEPLOY}/${T}_map --option $T
done
echo `date`
echo "Done loading memcache"

