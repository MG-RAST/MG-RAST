#!/bin/bash

LOAD=$HOME/ach/md52memcache.pl
DEPLOY=/mnt/ach
VACH='1'
MKEY='_ach'
MHOST='localhost:11211'
TYPES=( 'source' 'organism' 'function' 'ontology' 'md5_lca' 'md5_protein' 'md5_rna' 'md5_ontology' 'md5' )

sudo mkdir $DEPLOY
sudo chown ${USER}:${USER} $DEPLOY

for T in "${TYPES[@]}"; do
    echo "downloading $T ..."
    wget -q -O ${DEPLOY}/${T}_map.gz ftp://ftp.metagenomics.anl.gov/data/MD5nr/memcached/v${VACH}/${T}_map.gz
    echo "gunzipping $T ..."
    gunzip -v ${DEPLOY}/${T}_map.gz
    echo "loading $T ..."
    $LOAD --verbose --mem_host $MHOST --mem_key $MKEY --map ${DEPLOY}/${T}_map --option $T
done
echo "Done loading memcache"

