#!/bin/sh

HELP=0
CASS_CONF=''
CASS_DIR=''
KEYSPACE=''
TABLE=''
INFILE=''
OUTDIR=''
JAVA=`which java`

while getopts hc:d:k:t:i:o: option; do
    case "${option}"
        in
            h) HELP=1;;
            c) CASS_CONF=${OPTARG};;
            d) CASS_DIR=${OPTARG};;
            k) KEYSPACE=${OPTARG};;
            t) TABLE=${OPTARG};;
            i) INFILE=${OPTARG};;
            o) OUTDIR=${OPTARG};;
    esac
done

USAGE="Usage: BulkLoader.sh [-h] -c <cassandra config file> -d <cassandra lib dir> -k <keyspace> -t <table> -i <csv_file> -o <output dir>"

# check options
if [ $HELP -eq 1 ]; then
    echo $USAGE
    exit
fi
if [ -z "$KEYSPACE" ] || [ -z "$TABLE" ] || [ -z "$INFILE" ]; then
    echo "[error] missing parameter"
    echo $USAGE
    exit
fi
if [ ! -f "$INFILE" ]; then
    echo "[error] file $INFILE does not exist"
    echo $USAGE
    exit
fi
if [ -z "$OUTDIR" ]; then
    OUTDIR=/var/lib/cassandra/sstable
fi
if [ -z "$CASS_CONF" ]; then
    CASS_CONF=/etc/cassandra/cassandra.yaml
fi
if [ -z "$CASS_DIR" ]; then
    CASS_DIR=/usr/share/cassandra
fi

# set classpath
THIS_DIR=`pwd`
CLASSPATH=".:$THIS_DIR/*:$CASS_CONF:$CASS_DIR/*:$CASS_DIR/lib/*"

# Compile
echo "compile: javac -cp $CLASSPATH BulkLoader.java"
javac -cp $CLASSPATH BulkLoader.java

# Import
echo
echo "run: $JAVA -ea -cp $CLASSPATH -Xms20G -Xmx20G -Dlog4j.configuration=log4j-tools.properties BulkLoader $KEYSPACE $TABLE $INFILE $OUTDIR"
$JAVA -ea -cp $CLASSPATH -Xms20G -Xmx20G -Dlog4j.configuration=log4j-tools.properties BulkLoader $KEYSPACE $TABLE $INFILE $OUTDIR

