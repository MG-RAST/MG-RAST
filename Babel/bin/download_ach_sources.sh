#!/bin/sh

if [ $# -ne 1 ]
then
    echo "USAGE: download_ach_sources.sh <download dir>"
    exit 1
fi

# Config
DOWNLOAD_DIR=$1
SOURCES="eggNOG GO Greengenes IMG KEGG KO NR PATRIC RefSeq RDP SEED SILVA UniProt"

echo Starting Download for ACH `date`

echo Checking destination 
for d in ${SOURCES}
do
    if [ -d ${DOWNLOAD_DIR}/$d ] ; then
	echo Found destination directory for $d
    else
	echo Missing destination directory for $d
	echo Creating directory for $d
	mkdir -m 775 ${DOWNLOAD_DIR}/$d
    fi
done

echo Downloading eggNOG `date`
wget -v -N -P ${DOWNLOAD_DIR}/eggNOG http://eggnog.embl.de/download/protein.sequences.v2.fa.gz
wget -v -N -P ${DOWNLOAD_DIR}/eggNOG http://eggnog.embl.de/download/COG.mapping.txt.gz
wget -v -N -P ${DOWNLOAD_DIR}/eggNOG http://eggnog.embl.de/download/NOG.mapping.txt.gz

echo Downloading GO hierarchy `date`
time lftp -c "open -e 'mirror -v --no-recursion -I gene_ontology.1_2.obo /pub/go/ontology/obo_format_1_2/ ${DOWNLOAD_DIR}/GO' ftp://ftp.geneontology.org"

echo Downloading Greengenes `date`
wget -v -N -P ${DOWNLOAD_DIR}/Greengenes http://greengenes.lbl.gov/Download/Sequence_Data/Greengenes_format/greengenes16SrRNAgenes.txt.gz

echo Downloading IMG `date`

echo Download KEGG `date`
time lftp -c "open -e 'mirror -v --no-recursion -I genome /pub/kegg/genes/ ${DOWNLOAD_DIR}/KEGG' ftp://ftp.genome.ad.jp"
time lftp -c "open -e 'mirror -v --no-recursion -I genes.tar.gz /pub/kegg/release/current/ ${DOWNLOAD_DIR}/KEGG' ftp://ftp.genome.ad.jp"

echo Download KO `date`
time lftp -c "open -e 'mirror -v --no-recursion -I ko /pub/kegg/genes/ ${DOWNLOAD_DIR}/KO' ftp://ftp.genome.ad.jp"
time lftp -c "open -e 'mirror -v --parallel=2 -I *.keg /pub/kegg/brite/ko/ ${DOWNLOAD_DIR}/KO' ftp://ftp.genome.ad.jp"

echo Downloading NCBI NR `date`
time lftp -c "open -e 'mirror -v -e --no-recursion -I nr.gz /blast/db/FASTA ${DOWNLOAD_DIR}/NR' ftp://ftp.ncbi.nih.gov"

echo Downloading PATRIC `date`
time lftp -c "open -e 'mirror -v --parallel=2 -I *.PATRIC.gbf /patric2/genomes/ ${DOWNLOAD_DIR}/PATRIC' http://brcdownloads.vbi.vt.edu"

echo Downloading RefSeq `date`
time lftp -c "open -e 'mirror -v -e --delete-first -I *.genomic.gbff.gz /refseq/release/complete ${DOWNLOAD_DIR}/RefSeq' ftp://ftp.ncbi.nih.gov"

echo Downloading RDP `date`
wget -v -N -P ${DOWNLOAD_DIR}/RDP http://rdp.cme.msu.edu/download/release10_22_unaligned.gb.gz

echo Downloading SEED `date`
time lftp -c "open -e 'mirror -v --no-recursion -I md52id2func.gz /AnnotationClearingHouse/ ${DOWNLOAD_DIR}/SEED' ftp://ftp.theseed.org"
time lftp -c "open -e 'mirror -v --no-recursion -I subsystems2role.gz /subsystems/ ${DOWNLOAD_DIR}/SEED' ftp://ftp.theseed.org"

echo Downloading SILVA `date`
wget -v -N -P ${DOWNLOAD_DIR}/SILVA http://www.arb-silva.de/no_cache/download/archive/release_104/Exports/lsu-parc.fasta.tgz
wget -v -N -P ${DOWNLOAD_DIR}/SILVA http://www.arb-silva.de/no_cache/download/archive/release_104/Exports/lsu-parc.rast
wget -v -N -P ${DOWNLOAD_DIR}/SILVA http://www.arb-silva.de/no_cache/download/archive/release_104/Exports/ssu-parc.fasta.tgz
wget -v -N -P ${DOWNLOAD_DIR}/SILVA http://www.arb-silva.de/no_cache/download/archive/release_104/Exports/ssu-parc.rast

echo Downloading Uniprot `date`
time lftp -c "open -e 'mirror -v -e --delete-first -I uniprot_sprot.dat.gz /pub/databases/uniprot/current_release/knowledgebase/complete ${DOWNLOAD_DIR}/UniProt' ftp.uniprot.org"
time lftp -c "open -e 'mirror -v -e --delete-first -I uniprot_trembl.dat.gz /pub/databases/uniprot/current_release/knowledgebase/complete ${DOWNLOAD_DIR}/UniProt' ftp.uniprot.org"

echo Done `date`
