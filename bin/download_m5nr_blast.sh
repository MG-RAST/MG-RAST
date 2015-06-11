#!/bin/bash

# set a default values
# m5nr blast files - 2.6 GB & 11.7 GB
M5NR_VERSIONS="20100309 20131215"
TARGET="/m5nr"

for i in $M5NR_VERSIONS; do
    M5NR_VERSION=$i
    VERSION_DIR=$TARGET/$M5NR_VERSION
    URL=ftp://ftp.metagenomics.anl.gov/data/MD5nr/${M5NR_VERSION}/md5nr.blast.tgz
    
    echo ""
    echo "TARGET = $TARGET"
    echo "M5NR_VERSION = $M5NR_VERSION"
    echo "URL = $URL"
    echo ""
    
    if [ -d ${VERSION_DIR} ]; then
        echo "Files already exist, not downloading"
    else
        echo "Downloading files"
        mkdir -p ${VERSION_DIR}
        curl -s "${URL}" | tar -zxvf - -C ${VERSION_DIR}
    fi
done
exit 0