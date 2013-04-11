#!/bin/sh

if [ $# -ne 1 ]
then
    echo "USAGE: download_ach_sources.sh <download dir>"
    exit 1
fi

# Config
DOWNLOAD_DIR=$1
SOURCES="eggNOG FungalDB GO Greengenes IMG InterPro KEGG KO NR PATRIC Phantome RefSeq RDP SEED SILVA UniProt"

echo Starting Download for ACH `date`

echo Checking destination 
for d in ${SOURCES}
do
    if [ -d ${DOWNLOAD_DIR}/$d ]; then
	echo Found destination directory for $d
    else
	echo Creating directory for $d
	mkdir -m 775 ${DOWNLOAD_DIR}/$d
    fi
done

echo Downloading eggNOG `date`
wget -v -N -P ${DOWNLOAD_DIR}/eggNOG http://eggnog.embl.de/version_3.0/data/downloads/fun.txt.gz
wget -v -N -P ${DOWNLOAD_DIR}/eggNOG http://eggnog.embl.de/version_3.0/data/downloads/UniProtAC2eggNOG.tsv.gz
wget -v -N -P ${DOWNLOAD_DIR}/eggNOG http://eggnog.embl.de/version_3.0/data/downloads/COG.funccat.txt.gz
wget -v -N -P ${DOWNLOAD_DIR}/eggNOG http://eggnog.embl.de/version_3.0/data/downloads/NOG.funccat.txt.gz
wget -v -N -P ${DOWNLOAD_DIR}/eggNOG http://eggnog.embl.de/version_3.0/data/downloads/COG.description.txt.gz
wget -v -N -P ${DOWNLOAD_DIR}/eggNOG http://eggnog.embl.de/version_3.0/data/downloads/NOG.description.txt.gz

echo Downloading FungalDB `date`
wget -v -N -P ${DOWNLOAD_DIR}/FungalDB http://fungalgenomes.org/public/mobedac/for_VAMPS/fungalITSdatabaseID.taxonomy.seqs.gz

#echo Downloading GO hierarchy `date`
#time lftp -c "open -e 'mirror -v --no-recursion -I gene_ontology.1_2.obo /pub/go/ontology/obo_format_1_2/ ${DOWNLOAD_DIR}/GO' ftp://ftp.geneontology.org"

echo Downloading Greengenes `date`
wget -v -N -P ${DOWNLOAD_DIR}/Greengenes http://greengenes.lbl.gov/Download/Sequence_Data/Fasta_data_files/current_GREENGENES_gg16S_unaligned.fasta.gz

echo Downloading IMG `date`
time lftp -c "open -e 'mirror -v --parallel=2 -I *.tar.gz /pub/IMG/img_core_v400/ ${DOWNLOAD_DIR}/IMG' ftp://ftp.jgi-psf.org"

echo Downloading InterPro `date`
time lftp -c "open -e 'mirror -v --no-recursion -I names.dat /pub/databases/interpro/ ${DOWNLOAD_DIR}/InterPro' ftp://ftp.ebi.ac.uk"

echo Download KEGG `date`
# ftp is no longer accessable
#time lftp -c "open -e 'mirror -v --no-recursion -I genome /pub/kegg/genes/ ${DOWNLOAD_DIR}/KEGG' ftp://ftp.genome.ad.jp"
#time lftp -c "open -e 'mirror -v --no-recursion -I genes.tar.gz /pub/kegg/release/current/ ${DOWNLOAD_DIR}/KEGG' ftp://ftp.genome.ad.jp"

echo Download KO `date`
# ftp is no longer accessable
#time lftp -c "open -e 'mirror -v --no-recursion -I ko /pub/kegg/genes/ ${DOWNLOAD_DIR}/KO' ftp://ftp.genome.ad.jp"
#time lftp -c "open -e 'mirror -v --parallel=2 -I *.keg /pub/kegg/brite/ko/ ${DOWNLOAD_DIR}/KO' ftp://ftp.genome.ad.jp"

echo Downloading NCBI NR `date`
time lftp -c "open -e 'mirror -v -e --no-recursion -I nr.gz /blast/db/FASTA/ ${DOWNLOAD_DIR}/NR' ftp://ftp.ncbi.nih.gov"

echo Downloading PATRIC `date`
time lftp -c "open -e 'mirror -v --parallel=2 -I *.PATRIC.gbf /patric2/genomes/ ${DOWNLOAD_DIR}/PATRIC' http://brcdownloads.vbi.vt.edu"

echo Downloading Phantome `date`
wget -v -N -P ${DOWNLOAD_DIR}/Phantome http://www.phantome.org/Downloads/proteins/all_sequences/phage_proteins_1364814002.fasta.gz

echo Downloading RefSeq `date`
time lftp -c "open -e 'mirror -v -e --delete-first -I *.genomic.gbff.gz /refseq/release/complete/ ${DOWNLOAD_DIR}/RefSeq' ftp://ftp.ncbi.nih.gov"

echo Downloading RDP `date`
wget -v -N -P ${DOWNLOAD_DIR}/RDP http://rdp.cme.msu.edu/download/release10_31_unaligned.gb.gz

echo Downloading SEED `date`
time lftp -c "open -e 'mirror -v --no-recursion -I SEED.fasta /misc/Data/idmapping/ ${DOWNLOAD_DIR}/SEED' ftp://ftp.theseed.org"
time lftp -c "open -e 'mirror -v --no-recursion -I subsystems2role.gz /subsystems/ ${DOWNLOAD_DIR}/SEED' ftp://ftp.theseed.org"

echo Downloading SILVA `date`
wget -v -N -P ${DOWNLOAD_DIR}/SILVA http://www.arb-silva.de/no_cache/download/archive/release_108/Exports/lsu-parc.fasta.tgz
wget -v -N -P ${DOWNLOAD_DIR}/SILVA http://www.arb-silva.de/no_cache/download/archive/release_108/Exports/lsu-parc.rast.tgz
wget -v -N -P ${DOWNLOAD_DIR}/SILVA http://www.arb-silva.de/no_cache/download/archive/release_108/Exports/ssu-parc.fasta.tgz
wget -v -N -P ${DOWNLOAD_DIR}/SILVA http://www.arb-silva.de/no_cache/download/archive/release_108/Exports/ssu-parc.rast.tgz

echo Downloading Uniprot `date`
time lftp -c "open -e 'mirror -v -e --delete-first -I uniprot_sprot.dat.gz /pub/databases/uniprot/current_release/knowledgebase/complete ${DOWNLOAD_DIR}/UniProt' ftp.uniprot.org"
time lftp -c "open -e 'mirror -v -e --delete-first -I uniprot_trembl.dat.gz /pub/databases/uniprot/current_release/knowledgebase/complete ${DOWNLOAD_DIR}/UniProt' ftp.uniprot.org"

echo Done `date`
