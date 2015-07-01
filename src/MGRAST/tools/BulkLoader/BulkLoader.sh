#!/bin/sh

HELP=0
CASS_DIR=''
KEYSPACE=''
TABLE=''
INFILE=''
OUTDIR=''
JAVA=`which java`

while getopts hc:k:t:i:o: option; do
    case "${option}"
        in
            h) HELP=1;;
            c) CASS_DIR=${OPTARG};;
            k) KEYSPACE=${OPTARG};;
            t) TABLE=${OPTARG};;
            i) INFILE=${OPTARG};;
            o) OUTDIR=${OPTARG};;
    esac
done

USAGE="Usage: BulkLoader.sh [-h] -c <cassandra dir> -k <keyspace> -t <table> -i <csv_file> -o <output dir>"

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
    OUTDIR=/data/sstable
fi
if [ -z "$CASS_DIR" ]; then
    CASS_DIR=/opt/cassandra
fi

# set classpath
CLASSPATH=".:$CASS_DIR/conf/cassandra.yaml:$CASS_DIR/lib/*"

# Compile
echo "compile: javac -cp $CLASSPATH BulkLoader.java"
javac -cp $CLASSPATH BulkLoader.java

# Import
echo
echo "run: $JAVA -ea -cp $CLASSPATH -Xms20G -Xmx20G -Dlog4j.configuration=log4j-tools.properties BulkLoader $KEYSPACE $TABLE $INFILE $OUTDIR"
$JAVA -ea -cp $CLASSPATH -Xms20G -Xmx20G -Dlog4j.configuration=log4j-tools.properties BulkLoader $KEYSPACE $TABLE $INFILE $OUTDIR

