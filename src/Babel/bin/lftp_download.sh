echo Downloading Refseq `date`
lftp -c 'open -e "mirror -e --delete-first /refseq/release/ /vol/biodb/ncbi/refseq" ftp://ftp.ncbi.nih.gov'
echo Downloading NCBI NR
time lftp -c 'open -e "mirror -e --delete-first -I nr* --no-recursion /blast/db/ /vol/biodb/ncbi/ncbi_fasta_files" ftp://ftp.ncbi.nih.gov'
echo Downloading Uniprot
time lftp -c 'open -e"mirror -e --parallel=2 /pub/databases/uniprot/current_release/knowledgebase/complete /vol/biodb/uniprot/current_release/complete/" ftp.uniprot.org'
echo Download KEGG
time lftp -c 'open -e"mirror --delete --parallel=2 /pub/kegg/release/current/ /vol/biodb/kegg/current" ftp://ftp.genome.ad.jp'
