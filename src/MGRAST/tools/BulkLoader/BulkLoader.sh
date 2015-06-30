#!/bin/sh

HELP=0
KEYSPACE=''
TABLE=''
INFILE=''
OUTDIR=''
JAVA=`which java`
JARS="/root/cassandra/lib /root/opencsv"

while getopts hk:t:i:o: option; do
    case "${option}"
        in
            h) HELP=1;;
            k) KEYSPACE=${OPTARG};;
            t) TABLE=${OPTARG};;
            i) INFILE=${OPTARG};;
            o) OUTDIR=${OPTARG};;
    esac
done

USAGE="Usage: BulkLoader.sh [-h] -k <keyspace> -t <table> -i <csv_file> -o <output dir>"

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
    OUTDIR=/mnt/sstable
fi

# check env
if [ -z "$CASSANDRA_CONFIG" ]; then
    CASSANDRA_CONFIG=/root/cassandra/conf/cassandra.yaml
fi

# set classpath
CLASSPATH=".:$CASSANDRA_CONFIG"
for path in $JARS; do
    CLASSPATH="$CLASSPATH:$path/*"
done

# Compile
echo "compile: javac -cp $CLASSPATH BulkLoader.java"
javac -cp $CLASSPATH BulkLoader.java

# Import
echo
echo "run: $JAVA -ea -cp $CLASSPATH -Xms20G -Xmx20G -Dlog4j.configuration=log4j-tools.properties BulkLoader $KEYSPACE $TABLE $INFILE $OUTDIR"
$JAVA -ea -cp $CLASSPATH -Xms20G -Xmx20G -Dlog4j.configuration=log4j-tools.properties BulkLoader $KEYSPACE $TABLE $INFILE $OUTDIR

