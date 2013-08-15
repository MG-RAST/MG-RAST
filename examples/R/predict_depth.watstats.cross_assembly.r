predict_depth.cross <- function(
                                abundance_matrix,
                                col_nums=c(1,2),
                                num_reads = 1000000,
                                input_type = "object",
                                file_out_prefix = "depth_prediction.cross",
                                genome_size=4000000,
                                scale_by_unannotated = TRUE,
                                read_length = 125,
                                min_overlap = 30,
                                num_to_show=10,
                                create_figure=FALSE,
                                debug=FALSE
                                )
{

  # This script can predict sequencing depth for wgs data from 16s based counts

  # load packages
  require(hash)
  require(RJSONIO)
  require(RCurl)
  
  # Print usage if
  if (nargs() == 0){print_usage()}

  # Check to see if abundance_matrix is a file - if so, load it - if not, assume it is an R object and copy it
  if (input_type=="file"){
    my_data_matrix <- data.matrix(read.table(abundance_matrix, row.names=1, check.names=FALSE, header=TRUE, sep="\t", comment.char="", quote=""))
  }else{
    my_data_matrix <- abundance_matrix
  }

  # hashes to store the data
  summed_data_hash <- hash()
  sample_names_hash <<- hash()
  unannotated_counts_hash <- hash()

  # process each column to produce a single summed profile
  for ( col_index in 1:length(col_nums)){

    # get the id and counts for the selected column
    my_column <- col_nums[col_index]
    my_col_id <- dimnames(my_data_matrix)[[2]][my_column]
    
    # calculate and sum lander waterman stats
    summed_data_hash <- process_column( my_matrix = my_data_matrix, my_col = my_column, my_hash = summed_data_hash, debug=debug )

    # calculate running sum of unannotated reads
    if ( scale_by_unannotated == TRUE ) {
      unannotated_counts_hash <- get_unannotated( my_id=my_col_id, my_hash2=unannotated_counts_hash )
    }
    
    # save the id's
    sample_names_hash[ my_col_id ] <<- 1
       
    if (debug==TRUE) { print(paste("hash first entry::  key: ", keys(summed_data_hash)[1], " value:", summed_data_hash[[ keys(summed_data_hash)[1] ]], sep="")) }
    
  }

  # Create an array from the hash 
  summed_data_matrix <<- matrix(0, length(keys(summed_data_hash)), 1)

  dimnames(summed_data_matrix)[[1]] <<- c(rep("",length(keys(summed_data_hash))))
  
  for (z in 1:length(keys(summed_data_hash))){
    dimnames(summed_data_matrix)[[1]][z] <<- keys(summed_data_hash)[z]
    summed_data_matrix[z,] <<- summed_data_hash[[ keys(summed_data_hash)[z] ]]
  }

  # get index of exisiting order
  summed_data_matrix_index <<- as.vector(order(summed_data_matrix[,1], decreasing=TRUE))

  # create index sorted matrix # this preserves the row names, but not columns
  sorted.summed_data_matrix <<- as.matrix(summed_data_matrix[summed_data_matrix_index,])

  # create matrix to hold calcualted depths
  my_coverage_matrix <<- matrix("",dim(sorted.summed_data_matrix)[1],6)
  dimnames(my_coverage_matrix)[[1]] <- dimnames(sorted.summed_data_matrix)[[1]] # label rows
  dimnames(my_coverage_matrix)[[2]] <- c(
                                         paste(unlist(keys(sample_names_hash)), collapse=":"),  ######## <-- start here (get mgm names)
                                         "coverage_redundancy",
                                         "expected_num_contigs",
                                         "expected_seqs_per_contig",
                                         "expected_contig_length",
                                         "expected_coverage"
                                         ) # label columns
  my_coverage_matrix[,1] <- sorted.summed_data_matrix[,1] # place abundance in first column
    
  for (i in 1:dim(sorted.summed_data_matrix)[1]){
      # calculate sequencing depth for each taxon (include portion unannotated)

    if ( scale_by_unannotated == TRUE ) {
      percent_reads <- ( sorted.summed_data_matrix[i,1] / ( sum(sorted.summed_data_matrix[,1]) + unannotated_counts_hash[[ "unannotated_counts" ]] ) ) * 100 # use unannotated counts
    }else{
      percent_reads <- ( sorted.summed_data_matrix[i,1] / ( sum(sorted.summed_data_matrix[,1]) ) ) * 100 # ignore unannotated counts
    }
      # Get the watstats for the current taxa

    if( sorted.summed_data_matrix[i,1] > 0 ){ # only perform calculation on counts > 0
    
      my_watstats <- watstats(
                              # num_reads = sum(sorted.summed_data_matrix[,1]),
                              num_reads = num_reads,
                              percent_data = percent_reads,
                              genome_length = genome_size,
                              read_length = read_length,
                              min_overlap = min_overlap,
                              sample_name = dimnames(sorted.summed_data_matrix[[1]][i])
                              )
    
      my_coverage_matrix[i,2] <- my_watstats[1] # my_watstats.coverage_redundancy
      my_coverage_matrix[i,3] <- my_watstats[2] # my_watstats.num_contigs
      my_coverage_matrix[i,4] <- my_watstats[3] # my_watstats.seqs_per_contig
      my_coverage_matrix[i,5] <- my_watstats[4] # my_watstats.contig_length
      my_coverage_matrix[i,6] <- my_watstats[5] # my_watstats.percent_coverage
      
    }else{

      my_coverage_matrix[i,2] <- 0 #my_watstats[1] # my_watstats.coverage_redundancy
      my_coverage_matrix[i,3] <- 0 #my_watstats[2] # my_watstats.num_contigs
      my_coverage_matrix[i,4] <- 0 #my_watstats[3] # my_watstats.seqs_per_contig
      my_coverage_matrix[i,5] <- 0 #my_watstats[4] # my_watstats.contig_length
      my_coverage_matrix[i,6] <- 0 #my_watstats[5] # my_watstats.percent_coverage
      
    }
    
  }

  # generate tab delimited output
  file_out <- gsub(" ", "", paste(file_out_prefix, ".txt"))
  write.table(my_coverage_matrix, file = file_out, col.names=NA, row.names = TRUE, sep="\t", quote=FALSE)
  
  # generate a figure 
  if (create_figure == TRUE){
    image_out <- gsub(" ", "", paste(file_out_prefix, ".jpg"))
    jpeg(filename=image_out, width = 960, height = 480)
    par(mar=c(15,5,1,5))
    barplot( as.numeric(sorted.summed_data_matrix[1:num_to_show,1]), log="y",las=2, axisnames=(1:10), names.arg = dimnames(my_coverage_matrix)[[1]][1:num_to_show], ylab="" ) # mar=c(1,1,1,50))
    mtext("Taxon Abundance", side=2, line=4 )
    par(new=TRUE)
    plot((1:num_to_show), my_coverage_matrix[1:num_to_show,2], type="o", col="red", lwd=3, lty=1, xlab="", ylab="", xaxt="n", axes=F)
    #axis(2, las=1)
    #mtext("Taxon Abundance", side=2, line=1 )
    axis(4, las=1, col="red")
    mtext( paste("Predicted BPs of sequencing for (", coverage, ") x coverage"),side=4, line=4, adj=1.3, col = "red")
    dev.off()
  }

}








###### SUBS #####

###### hash the counts for all the selected columns together

process_column <- function ( my_matrix, my_col, my_hash, debug ){
  
  col_matrix <- as.matrix(my_matrix[,my_col])
  
  dimnames(col_matrix)[[2]] <- list(dimnames(my_matrix)[[2]][my_col])

  for ( y in 1:dim(col_matrix)[1] ){

    line_annotation_character <- as.character(dimnames(col_matrix)[[1]][y])
    
    line_count_numeric <- as.numeric(col_matrix[y,1])
    
    if ( has.key(line_annotation_character, my_hash)==TRUE ){
          my_hash[ line_annotation_character ] <- my_hash[[ line_annotation_character ]] + line_count_numeric
        }else{
          my_hash[ line_annotation_character ] <- line_count_numeric
        }

  }
  
  return(my_hash)

}




###### get the counts for the unannotated reads
get_unannotated <- function( my_id, my_hash2 ){
  
  if ( grepl("^mgm", my_id)==TRUE ){ # remove "mgm" from id if it's there
    mgid <- gsub("mgm", "", as.character(my_id))
  }else{
    mgid <- as.character(my_id)
  }
    
  # First - curl the necessary data from the API,
  sequence_stats.call <-  paste("http://api.metagenomics.anl.gov/metagenome_statistics/", mgid, sep="")
  sequence_stats.json <- fromJSON(getURL(sequence_stats.call))

  # then calculate number of unannotated and add it to the running total
  num_reads_raw <- as.integer(sequence_stats.json['sequence_count_raw'])
  num_reads_annotated <- as.integer(sequence_stats.json['read_count_annotated'])
  num_reads_not_annotated <- ( num_reads_raw - num_reads_annotated )

  if ( has.key(line_annotation_character, unannotated_counts_hash)==TRUE ){
    unannotated_counts_hash[ "unannotated_counts" ] <- unannotated_counts_hash[[ "unannotated_counts" ]] + num_reads_not_annotated
  }else{
    my_hash[ "unannotated_counts" ] <- num_reads_not_annotated
  }

  return(my_hash2)
  
}



###### USAGE
print_usage <- function() {
  writeLines(
             "  ------------------------------------------------------------------------------
  predict_depth.cross.r                     Kevin P. Keegan, kkeegan@anl.gov  Feb 2013
  ------------------------------------------------------------------------------
  DESCRIPTION:
  Script to predict amount of WGS sequencing necessary to achieve a certain level of
  coverage based on relative organism abundance determined from 16s data.
  This version of the function will combine counts from multiple input columns
  to produce predictions for cross assembly

  USAGE:
  predict_depth(
                abundance_matrix,
                col_nums=c(1,2),
                num_reads = 1000000,
                input_type = \"object\",
                file_out_prefix = \"depth_prediction.cross\",
                genome_size=4000000,
                read_length = 125,
                min_overlap = 30,
                num_to_show=10,
                create_figure=FALSE,
                debug=FALSE
                )

  NOTES:

  abundance_matrix : can be a file or R matrix - specify file or it will treat like R matrix
  an output tab delimited text is always created, a pdf is output is optional.
  Calculation is performed on all taxa - but only shows as many as specified by
  num_to_show. Should be output of process_LCA_counts

  Two most commone ways to use this script would be like this for an R object:
       predict_depth(my_data.matrix)
  or like this for a tab delimited file as input
       predict_depth(\"test_data.txt\", input_type=\"file\")

  In either case, input is a matrix, first column with taxa names, remaining
  with abundance profiles for some number of metagenomes.

  Program only processes the selected column from the input matrix
  ------------------------------------------------------------------------------"
             )
  stop("you did not enter the correct args -- see above")
}



###### watstats - adapeted from Folker Meyers perl script
watstats <- function (
                      num_reads = 1000000,
                      percent_data = 20, # use to get num reads
                      genome_length = 4000000,
                      read_length = 125,
                      min_overlap = 30,
                      verbose=FALSE,
                      sample_name = "na"
                      ) {

     taxa_num_reads = ( num_reads * ( percent_data/100 ) ) # determine number of reads that are of taxa i 
     
     alpha    <- ( taxa_num_reads/genome_length ) # $alpha=$N/$GM; # $GM = $G*1000; (input in original was in KB)
     theta    <- ( min_overlap/read_length )      # $theta=$T/$L;
     sigma    <- ( 1-theta )                      # $sigma=1-$theta;

     coverage_redundancy <- ( (read_length*taxa_num_reads)/genome_length )          # $c=$L*$N/$GM;

     num_contigs      <- taxa_num_reads*exp(-coverage_redundancy*sigma)    # $i  =$N*exp(-$c*$sigma); 
     if ( num_contigs < 1 ){ num_contigs <- 1 }                            # $i=1    if $i   < 1;
     if ( num_contigs > num_reads ){ num_contigs <- num_reads }            # $i  =$N if $i   > $N;
     
     seqs_per_contig  <- exp(coverage_redundancy*sigma)                             # exp($c*$sigma);
     if ( seqs_per_contig > num_reads ){ seqs_per_contig <- num_reads }             # $iii=$N if $iii > $N;
     if ( seqs_per_contig < 1 ){ seqs_per_contig <- 1 }                             # $iii=1  if $iii < 1;

     contig_length    <- read_length*(((exp(coverage_redundancy*sigma)-1)/coverage_redundancy)+(1-sigma)) # $iv=int($L*(((exp($c*$sigma)-1)/$c)+(1-$sigma)));
     if ( contig_length > genome_length ){ contig_length <- genome_length }         # $iv=$GM if $iv  > $GM;
  
     percent_coverage <- 100*num_contigs*contig_length/genome_length                # $compl=int(100*$i*$iv/$GM);
     if ( percent_coverage > 100 ){ percent_coverage <- 100 }
     
     if( verbose==TRUE ){
       print(paste("INPUT               ",sample_name))
       print(paste("num_reads           :", round(taxa_num_reads, digits=0)))
       print(paste("percent_data        :", round(percent_data, digits=1)))
       print(paste("genome_length       :", round(genome_length, digits=0)))
       print(paste("read_length         :", round(read_length,digits=0)))
       print(paste("min_overlap         :", round(min_overlap, digits=0)))
       print("")
       print("OUTPUT")
       print(paste("coverage_redundancy :", round(coverage_redundancy, digits=1)))
       print(paste("num_contigs         :", round(num_contigs, digits=1)))
       print(paste("seqs_per_contig     :", round(seqs_per_contig, digits=1)))
       print(paste("contig_length       :", round(contig_length, digits=1)))
       print(paste("percent_coverage    :", round(percent_coverage, digits=1), "%"))
       print('------------------------------------------------------')
     }
     
     my_results <- c(coverage_redundancy, num_contigs, seqs_per_contig, contig_length, percent_coverage)
     
     return(my_results)
     
  }
