MGRAST_preprocessing <<- function(file_in,     # name of the input file (tab delimited text with the raw counts) or R matrix
                                  data_type             = "file",  # c(file, r_matrix)
                                  output_object         = "default", # output R object (matrix)
                                  file_out              = "default", # output flat file                       
                                  remove_sg             = TRUE, # boolean to remove singleton counts
                                  remove_sg_valueMin    = 1, # lowest retained value (lower converted to 0)
                                  sg_threshold          = 1, # lowest retained row sum (lower, row is removed)
                                  log_transform         = FALSE,
                                  norm_method           = "DESeq_blind", #c("standardize", "quantile", "DESeq_blind", "DESeq_per_condition", "DESeq_pooled", "DESeq_pooled_CR", "none"), # USE blind if not replicates -- use pooled to get DESeq default
                                  pseudo_count          = 1, # has to be integer for DESeq
                                  DESeq_metadata_table  = NA, # only used if method is other than "blind"
                                  DESeq_metadata_column = 1, # only used if method is other than "blind"
                                  DESeq_metadata_type   = "file",           # c( "file", "r_matrix" )
                                  #DESeq_method          = "blind",  # c( "pooled", "pooled-CR", "per-condition", "blind" ) # blind, treat everything as one group
                                  DESeq_sharingMode     = "maximum",  # c( "maximum", "fit-only", "gene-est-only" ) # maximum is the most conservative choice
                                  DESeq_fitType         = "local",          # c( "parametric", "local" )
                                  DESeq_image           = FALSE, # create dispersion vs mean plot indicate DESeq regression
                                  scale_0_to_1          = TRUE,
                                  produce_fig           = FALSE,
                                  image_out             = "default",
                                  boxplot_height_in     = "default", # 11,
                                  boxplot_width_in      = "default", #"8.5,
                                  boxplot_res_dpi       = 300,
                                  create_log            = TRUE,
                                  debug                 = FALSE                                  
                                  )

  {
    
    # check for necessary packages, install if they are not there
    #require(matR) || install.packages("matR", repo="http://mcs.anl.gov/~braithwaite/R", type="source")
    #chooseCRANmirror()
    #setRepositories(ind=1:8)
    #source("http://bioconductor.org/biocLite.R")
    #require(preprocessCore) || install.packages("preprocessCore")
    #require(DESeq) || biocLite("DESeq") # update to DESeq2 when I have a chance
    #if ( is.element("RColorBrewer", installed.packages()[,1]) == FALSE ){ install.packages("RColorBrewer") }
    #if ( is.element("preprocessCore", installed.packages()[,1]) == FALSE ){ biocLite("preprocessCore") }
    #if ( is.element("DESeq", installed.packages()[,1]) == FALSE ){ biocLite("DESeq") }
    # (DESeq): www.ncbi.nlm.nih.gov/pubmed/20979621
    suppressPackageStartupMessages(library(preprocessCore))
    suppressPackageStartupMessages(library(DESeq))
    suppressPackageStartupMessages(library(RColorBrewer))
    ###### MAIN
    
    # get the name of the data object if an object is used -- use the filename if input is filename string
    if ( identical( data_type, "file") ){
      input_name <- file_in
    }else if( identical( data_type, "r_matrix") ){
      input_name <- deparse(substitute(file_in))
    }else{
      stop( paste( data_type, " is not a valid option for data_type", sep="", collapse=""))
    }    

    # Generate names for the output file and object
    if ( identical( output_object, "default") ){
      output_object <- paste( input_name, ".", norm_method, ".PREPROCESSED" , sep="", collapse="")
    }
    if ( identical( file_out, "default") ){
      file_out <- paste( input_name, ".", norm_method, ".PREPROCESSED.txt" , sep="", collapse="")
    }

    # Input the data
    if ( identical( data_type, "file") ){
      input_data <- data.matrix(read.table(file_in, row.names=1, header=TRUE, sep="\t", comment.char="", quote="", check.names=FALSE))
    }else if( identical( data_type, "r_matrix") ){
      input_data <- data.matrix(file_in)
    }else{
      stop( paste( data_type, " is not a valid option for data_type", sep="", collapse=""))
    }
    
    # sort the data (COLUMNWISE) by id
    sample_names <- order(colnames(input_data))
    input_data <- input_data[,sample_names]
    
    # make a copy of the input data that is not processed
    input_data.og <- input_data
 
    # non optional, convert "na's" to 0
    input_data[is.na(input_data)] <- 0
    
    # remove singletons
    if(remove_sg==TRUE){
      input_data <- remove.singletons(x=input_data, lim.entry=remove_sg_valueMin, lim.row=sg_threshold, debug=debug)
    }
    
    # log transform log(x+1)2
    if ( log_transform==TRUE ){
      input_data <- log_data(input_data)
    }

    regression_message <- "DESeq regression:      NA"
    # Normalize -- stadardize or quantile norm (depends on user selection)
    switch(
           norm_method,
           
           standardize={
             input_data <- standardize_data(input_data)
           },

           quantile={
             input_data <- quantile_norm_data(input_data)
           },

           DESeq_blind={
             regression_filename = paste(  input_name, ".DESeq_regression.png", sep="", collapse="" )
             regression_message <- paste("DESeq regression:      ", regression_filename, sep="", collapse="" )
             input_data <- DESeq_norm_data(input_data, regression_filename, pseudo_count,
                                           DESeq_metadata_table, DESeq_metadata_column, sample_names,
                                           DESeq_method="blind", DESeq_sharingMode, DESeq_fitType, DESeq_image, debug)
           },

           DESeq_per_condition={
             stop( cat("The DESeq_per_condition option does not work as it should. DESeq authors advise using the pooled method (DESeq_pooled here) instead.\n
You can accomplish a normalization equivalent to per-condition if you break your data into one matrix per-condition and use the pooled option.
Given that the method athors advise using the pooled methods anyways, I don't plan to fix this unless it is requested. For future reference, it
works up through estimateDispersions(), but fails on varianceStabilizingTransformation().  I can't find examples - and would not be able to debug
quickly"
                       ))
             #if( is.na(DESeq_metadata_table) ){ stop("To DESeq_norm_by_group you must specify a DESeq_metadata_table") }
             #regression_filename = paste(  input_name, ".DESeq_regression.png", sep="", collapse="" )
             #regression_message <- paste("DESeq regression:      ", regression_filename, sep="", collapse="" )
             #input_data <- DESeq_norm_data(input_data, regression_filename, pseudo_count,
             #                              DESeq_metadata_table, DESeq_metadata_column, sample_names,
             #                              DESeq_method="per-condition", DESeq_sharingMode, DESeq_fitType, DESeq_image, debug)    
           },
           
           DESeq_pooled={
             if( is.na(DESeq_metadata_table) ){ stop("To DESeq_pooled you must specify a DESeq_metadata_table") }
             regression_filename = paste(  input_name, ".DESeq_regression.png", sep="", collapse="" )
             regression_message <- paste("DESeq regression:      ", regression_filename, sep="", collapse="" )
             input_data <- DESeq_norm_data(input_data, regression_filename, pseudo_count,
                                           DESeq_metadata_table, DESeq_metadata_column, sample_names,
                                           DESeq_method="pooled", DESeq_sharingMode, DESeq_fitType, DESeq_image, debug)
           },

           DESeq_pooled_CR={
             if( is.na(DESeq_metadata_table) ){ stop("To DESeq_pooled_CR you must specify a DESeq_metadata_table") }             
             regression_filename = paste(  input_name, ".DESeq_regression.png", sep="", collapse="" )
             regression_message <- paste("DESeq regression:      ", regression_filename, sep="", collapse="" )
             input_data <- DESeq_norm_data(input_data, regression_filename, pseudo_count,
                                           DESeq_metadata_table, DESeq_metadata_column, sample_names,
                                           DESeq_method="pooled-CR", DESeq_sharingMode, DESeq_fitType, DESeq_image, debug)  
           },
             
           none={
             input_data <- input_data
           },
           {
             stop( paste( norm_method, " is not a valid option for method", sep="", collapse=""))
           }
           )
    
    # scale normalized data [max..min] to [0..1] over the entire dataset 
    if ( scale_0_to_1==TRUE ){
      input_data <- scale_data(input_data)
    }
    
    # create object, with specified name, that contains the preprocessed data
    do.call("<<-",list(output_object, input_data))
 
    # write flat file, with specified name, that contains the preprocessed data
    write.table(input_data, file=file_out, sep="\t", col.names = NA, row.names = TRUE, quote = FALSE, eol="\n")
    
    # produce boxplots
    boxplot_message <- "output boxplot:        NA"
    if ( produce_fig==TRUE ) {
    
      if( identical(image_out, "default") ){
        boxplots_file <- paste(input_name, ".boxplots.png", "\n", sep="", collapse="")
      }else{
        boxplots_file <- image_out
      }
      
      if( identical(boxplot_height_in, "default") ){ boxplot_height_in <- 8.5 }
      #if( identical(boxplot_width_in, "default") ){ boxplot_width_in <- round(ncol(input_data)/14) }
      if( identical(boxplot_width_in, "default") ){ boxplot_width_in <- 11 }

      png(
          filename = boxplots_file,
          height = boxplot_height_in,
          width = boxplot_width_in,
          res = boxplot_res_dpi,
          units = 'in'
          )
      plot.new()
      split.screen(c(2,1))
      screen(1)
      graphics::boxplot(input_data.og, main=(paste("RAW", sep="", collapse="")), las=2, cex.axis=0.5)
      screen(2)
      graphics::boxplot(input_data, main=(paste("PREPROCESSED (", norm_method, " norm)", sep="", collapse="")),las=2, cex.axis=0.5)
      dev.off()
      boxplot_message <- paste("output boxplot:       ", boxplots_file, "\n", sep="", collapse="")
    }

    # message to send to the user after completion, given names for object and flat file outputs
    #writeLines( paste("Data have been preprocessed. Proprocessed, see ", log_file, " for details", sep="", collapse=""))
    if ( create_log==TRUE ){
      # name log file
      log_file <- paste( file_out, ".log", sep="", collapse="")
      # write log
      writeLines(
                 paste(
                       "##############################################################\n",
                       "###################### INPUT PARAMETERS ######################\n",
                       "file_in:               ", file_in, "\n",
                       "data_type:             ", data_type, "\n",
                       "output_object:         ", output_object, "\n",
                       "file_out:              ", file_out, "\n",
                       "remove_sg:             ", as.character(remove_sg),
                       "remove_sg_valueMin:    ", remove_sg_valueMin, "\n",
                       "sg_threshold:          ", sg_threshold, "\n",
                       "log_transform          ", as.character(log_transform), "\n",
                       "norm_method:           ", norm_method, "\n",
                       "DESeq_metadata_table:  ", as.character(DESeq_metadata_table), "\n",
                       "DESeq_metadata_column: ", DESeq_metadata_column, "\n",
                       "DESeq_metadata_type:   ", DESeq_metadata_type, "\n",
                       #"DESeq_method:          ", DESeq_method, "\n",
                       "DESeq_sharingMode:     ", DESeq_sharingMode, "\n",
                       "DESeq_fitType:         ", DESeq_fitType, "\n",
                       "scale_0_to_1:          ", as.character(scale_0_to_1), "\n",
                       "produce_fig:           ", as.character(produce_fig), "\n",
                       "boxplot_height_in:     ", boxplot_height_in, "\n",
                       "boxplot_width_in:      ", boxplot_width_in, "\n",
                       "debug as.character:    ", as.character(debug), "\n",
                       "####################### OUTPUT SUMMARY #######################\n",
                       "output object:         ", output_object, "\n",
                       "output file:           ", file_out, "\n",
                       boxplot_message, "\n",
                       regression_message, "\n",
                       "##############################################################",
                       sep="", collapse=""
                       ),
                 con=log_file
                 )
    }
  }

######################################################################
######################################################################
### SUBS
######################################################################
######################################################################
    
######################################################################
### Load metadata (for groupings)    
######################################################################
load_metadata <- function(group_table, group_column, sample_names){
  metadata_matrix <- as.matrix( # Load the metadata table (same if you use one or all columns)
                               read.table(
                                          file=group_table,row.names=1,header=TRUE,sep="\t",
                                          colClasses = "character", check.names=FALSE,
                                          comment.char = "",quote="",fill=TRUE,blank.lines.skip=FALSE
                                          )
                               )
      
  #metadata_matrix <- metadata_matrix[ order(sample_names),,drop=FALSE ]
  group_names <- metadata_matrix[ order(sample_names), group_column,drop=FALSE ]
  return(group_names)
}
######################################################################

######################################################################
### Sub to remove singletons
######################################################################
remove.singletons <- function (x, lim.entry, lim.row, debug) {
  x <- as.matrix (x)
  x [is.na (x)] <- 0
  x [x < lim.entry] <- 0 # less than limit changed to 0
  #x [ apply(x, MARGIN = 1, sum) >= lim.row, ] # THIS DOES NOT WORK - KEEPS ORIGINAL MATRIX
  x <- x [ apply(x, MARGIN = 1, sum) >= lim.row, ] # row sum equal to or greater than limit is retained
  if (debug==TRUE){write.table(x, file="sg_removed.txt", sep="\t", col.names = NA, row.names = TRUE, quote = FALSE, eol="\n")}
  x  
}
######################################################################

# theMatrixWithoutRow5 = theMatrix[-5,]
# t1 <- t1[-(4:6),-(7:9)]
# mm2 <- mm[mm[,1]!=2,] # delete row if first column is 2
# data[rowSums(is.na(data)) != ncol(data),] # remove rows with any NAs

######################################################################
### Sub to log transform (base two of x+1)
######################################################################
log_data <- function(x, pseudo_count){
  x <- log2(x + pseudo_count)
  x
}
######################################################################

######################################################################
### sub to perform quantile normalization
######################################################################
quantile_norm_data <- function (x, ...){
  data_names <- dimnames(x)
  x <- normalize.quantiles(x)
  dimnames(x) <- data_names
  x
}
######################################################################

######################################################################
### sub to perform standardization
######################################################################
standardize_data <- function (x, ...){
  mu <- matrix(apply(x, 2, mean), nr = nrow(x), nc = ncol(x), byrow = TRUE)
  sigm <- apply(x, 2, sd)
  sigm <- matrix(ifelse(sigm == 0, 1, sigm), nr = nrow(x), nc = ncol(x), byrow = TRUE)
  x <- (x - mu)/sigm
  x
}
######################################################################

######################################################################
### sub to perform DESeq normalization
######################################################################
DESeq_norm_data <- function (x, regression_filename, pseudo_count,
                             DESeq_metadata_table, DESeq_metadata_column, sample_names,
                             DESeq_method, DESeq_sharingMode, DESeq_fitType, DESeq_image, debug, ...){
  # much of the code in this function is adapted/borrowed from two sources
  # Orignal DESeq publication www.ncbi.nlm.nih.gov/pubmed/20979621
  #     also see vignette("DESeq")
  # and Paul J. McMurdie's example analysis in a later paper http://www.ncbi.nlm.nih.gov/pubmed/24699258
  #     with supporing material # http://joey711.github.io/waste-not-supplemental/simulation-cluster-accuracy/simulation-cluster-accuracy-server.html
  if(debug==TRUE)(print("made it here DESeq (1)"))

  # check that pseudo counts are integer - must for DESeq
  if ( all.equal(pseudo_count, as.integer(pseudo_count)) != TRUE ){
    stop(paste("DESeq requires an integer pseudo_count, (", pseudo_count, ") is not an integer" ))
  }

  # import metadata matrix (from object or file)
  #if(!is.na(DESeq_metadata_table)){
  #  my_metadata <- load_metadata(DESeq_metadata_table, DESeq_metadata_column, sample_names)
  #}

  # create metdata for the "blind" case -- all samples treated as if they are in the same group
  if( identical(DESeq_method,"blind") ){
    my_conditions <- as.factor(rep(1,ncol(x)))
    if(debug==TRUE){my_conditions.test<<-my_conditions}
  }else{
    my_metadata <- load_metadata(DESeq_metadata_table, DESeq_metadata_column, sample_names)
    metadata_factors <- as.factor(my_metadata)
    if(debug==TRUE){my_metadata.test<<-my_metadata}
    my_conditions <- metadata_factors
    if(debug==TRUE){my_conditions.test<<-my_conditions}
  }

  if(debug==TRUE)(print("made it here DESeq (2)"))
  
  # add pseudocount to prevent workflow from crashing on NaNs - DESeq will crash on non integer counts
  x = x + pseudo_count 
 
  # create dataset object
  if(debug==TRUE){my_conditions.test<<-my_conditions}
  my_dataset <- newCountDataSet( x, my_conditions )
  if(debug==TRUE){my_dataset.test1 <<- my_dataset}
  if(debug==TRUE)(print("made it here DESeq (3)"))
  
  # estimate the size factors
  my_dataset <- estimateSizeFactors(my_dataset)

  if(debug==TRUE)(print("made it here DESeq (4)"))
  if(debug==TRUE){my_dataset.test2 <<- my_dataset}
  
  # estimate dispersions
  # reproduce this: deseq_varstab(physeq, method = "blind", sharingMode = "maximum", fitType = "local")
  #      see https://stat.ethz.ch/pipermail/bioconductor/2012-April/044901.html
  # with DESeq code directly
  # my_dataset <- estimateDispersions(my_dataset, method = "blind", sharingMode = "maximum", fitType="local")
  # but this is what they did in the supplemental material for the DESeq paper (I think) -- and in figure 1 of McMurdie et al.
  #my_dataset <- estimateDispersions(my_dataset, method = "pooled", sharingMode = "fit-only", fitType="local") ### THIS WORKS
  # This is what they suggest in the DESeq vignette for multiple replicats

  my_dataset <- estimateDispersions(my_dataset, method = DESeq_method, sharingMode = DESeq_sharingMode, fitType = DESeq_fitType)

  # in the case of per-condition, creates an envrionment called fitInfo
  # ls(my_dataset.test4@fitInfo)

  #  my_dataset <- estimateDispersions(my_dataset, method = DESeq_method, sharingMode = DESeq_sharingMode, fitType = DESeq_fitType)
  
  if(debug==TRUE){my_dataset.test3 <<- my_dataset}

  if(debug==TRUE)(print("made it here DESeq (5)"))
  
  # Determine which column(s) have the dispersion estimates
  dispcol = grep("disp\\_", colnames(fData(my_dataset)))

  # Enforce that there are no infinite values in the dispersion estimates
  #if (any(!is.finite(fData(my_dataset)[, dispcol]))) {
  #  fData(cds)[which(!is.finite(fData(my_dataset)[, dispcol])), dispcol] <- 0
  #}

  if(debug==TRUE)(print("made it here DESeq (6)"))
  
  # apply variance stabilization normalization
  #if ( identical(DESeq_method, "per-condition") ){

  # produce a plot of the regression
  if(DESeq_image==TRUE){
    png(
        filename = regression_filename,
        height = 8.5,
        width = 11,
        res = 300,
        units = 'in'
        )
        #plot.new()    
    plotDispEsts( my_dataset )
    dev.off()
  }

if(debug==TRUE)(print("made it here DESeq (7)"))
  
  my_dataset.normed <- varianceStabilizingTransformation(my_dataset)
  # ls(my_dataset.test4@fitInfo)
  # my_dataset.test4@fitInfo$Kirsten$fittedDispEsts

  if(debug==TRUE){my_dataset.test4 <<- my_dataset.normed}

  #}else{
   # my_dataset.normed <- varianceStabilizingTransformation(my_dataset)
  #}

  # return matrix of normed values
  x <- exprs(my_dataset.normed)
  x

}
######################################################################

######################################################################
### sub to scale dataset values from [min..max] to [0..1]
######################################################################
scale_data <- function(x){
  shift <- min(x, na.rm = TRUE)
  scale <- max(x, na.rm = TRUE) - shift
  if (scale != 0) x <- (x - shift)/scale
  x
}
######################################################################
