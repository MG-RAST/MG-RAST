MGRAST_preprocessing <<- function(file_in,     # name of the input file (tab delimited text with the raw counts)
                                  file_out                    = "preprocessed_data",    # name of the output data file (tab delimited text of preprocessed data)
                                  remove_sg                   =TRUE, # boolean to remove singleton counts
                                  sg_threshold                = 1, # rows with a sum of counts equal to or less than this value will be removed if remove_sg=TRUE 
                                  produce_fig                 = FALSE,     # boolean - to produce a figure (TRUE) or not (FALSE)
                                  image_out                   = "my_boxplots",   # name of the output image (the boxplot figure)
                                  raw_data_boxplot_title      = "raw data",   # title for the top (raw data boxplot)
                                  centered_data_boxplot_title = "log2(x+1) & centered per sample, scaled 0 to 1 over all samples", # title for the lower (preprocesed data) boxplot
                                  figure_width                = 950,                      # usually pixels, inches if eps is selected; png is default
                                  figure_height               = 1000,                     # usually pixels, inches if eps is selected; png is default
                                  figure_res                  = NA,                       # usually pixels, inches if eps is selected; png is default      
                                  debug                       = FALSE                     # print debug information          
                                  ) 

{

# Sub to remove singletons
  remove_singletons <- function(
                                my.matrix, abundance_limit = sg_threshold
                                )
    {
      dim_matrix <- dim(my.matrix)
      num_row <- dim_matrix[1]
      num_col <- dim_matrix[2]
      filtered.matrix <<- matrix(0,num_row,num_col)
      dimnames(filtered.matrix)[1] <<- dimnames(filtered.matrix)[1]
      dimnames(filtered.matrix)[2] <<- dimnames(filtered.matrix)[2]
      row_sums <<- matrix(0, num_row, 1)
      zero_row_count <<- 0
      # create a filtered matrix in with all NA's replaced with 0's
      my.matrix[ is.na(my.matrix) ]<-0
      # determine the sum of counts for each row
      for (i in 1:num_row){
        row_sums[i,1] <<- sum(my.matrix[i,])
        if ( row_sums[i,1] <= abundance_limit ){
          zero_row_count <<- zero_row_count + 1
        }
      }
      filtered.matrix <<- matrix(0, (num_row - zero_row_count), num_col)
      fail.list <<- vector(mode="list", length=zero_row_count)
      dimnames(filtered.matrix)[[2]] <<- dimnames(my.matrix)[[2]]
      dimnames(filtered.matrix)[[1]] <<- c(rep("", (num_row - zero_row_count))) # Fill this in below
      # now build a filtered matrix that tosses any rows entirely populated with zeros (anything with row count < abundance_limit)
      # as well as a list with the names of the rows that were tossed
      screen.row_count = 1
      zero.row_count = 1
      for (i in 1:num_row){
        if (row_sums[i,1] > abundance_limit){
          for (j in 1:num_col){
            filtered.matrix[screen.row_count, j] <<- my.matrix[i,j]
            dimnames(filtered.matrix)[[1]][screen.row_count] <<- dimnames(my.matrix)[[1]][i]
          }
          screen.row_count = screen.row_count + 1
        }else{
          fail.list[zero.row_count] <<- dimnames(my.matrix)[[1]][i]
          zero.row_count = zero.row_count + 1
        }
      }
      return(filtered.matrix)
    }

###### sub to import the input_file
#import_data <- function(file_name)
  {
    input_data = data.matrix(read.table(file_in, row.names=1, header=TRUE, sep="\t", comment.char="", quote=""))
  }
###### replace NA's with 0
  input_data[ is.na(input_data) ]<-0
  if( debug==TRUE ){ print(input_data) }
  
###### remove singletons
  if(remove_sg==TRUE){
    input_data <- remove_singletons( my.matrix=input_data, abundance_limit=sg_threshold)
  }
  if( debug==TRUE ){ print(input_data) }
  
###### get the diensions of the input object  
  number_entries = (dim(input_data)[1]) # number rows
  number_samples = (dim(input_data)[2]) # number columns

###### perform log transformation  
  log2_data = log2(input_data + 1)
  if( debug==TRUE ){ print(log2_data) }
  
###### create object to store data that are log transformed and centered  
  log2_cent_data <- matrix(0, number_entries, number_samples)

###### pull column and row names from the input_data   
  dimnames(log2_cent_data)[[2]] <- dimnames(input_data)[[2]] # colnames #edited 6-15-10
  dimnames(log2_cent_data)[[1]] <- dimnames(input_data)[[1]] # rownames #edited 6-15-10

###### center data from each sample (column)  
  for (i in 1:number_samples){ 
    sample = log2_data[,i]
    mean_sample = mean(sample) 
    stdev_sample = sd(sample)
    for (j in 1:number_entries){
      if ( stdev_sample==0 ){
        log2_cent_data[j,i] <- -10000 # silly fix for columns with stdev of 0 -- to make them look wacky
      }else{
        log2_cent_data[j,i] <- ((log2_data[j,i] - mean_sample)/stdev_sample)
      } 
    }
  }
  if( debug==TRUE ){ print(log2_cent_data) }

###### norm values from 0 to 1  
  min_value = min(log2_cent_data)
  for (i in 1:number_samples){ 
    for (j in 1:number_entries){
      log2_cent_data[j,i] <- (log2_cent_data[j,i] + abs(min_value))
    } 
  }
  if( debug==TRUE ){ print(log2_cent_data) }
  max_value= max(log2_cent_data)
  for (i in 1:number_samples){ 
    for (j in 1:number_entries){
      #if ( identical(NaN, log2_cent_data[j,i])  ){
      #}else{
        if ( log2_cent_data[j,i] == 0 | is.nan(log2_cent_data[j,i]) ){
          #log2_cent_data[j,i] <- -10000
        }else{
          log2_cent_data[j,i] <- ((log2_cent_data[j,i]/max_value))
        }
      #}
    }
  }
  #if( debug==TRUE ){ print(log2_cent_data) }


###### write the log transformed and centered data to a file
  write.table(log2_cent_data, file=file_out, sep="\t", col.names = NA, row.names = TRUE, quote = FALSE)

  if (produce_fig == TRUE){  # optional - produce an out put image
    suppressPackageStartupMessages(library(Cairo))
    CairoPNG(image_out, width = figure_width, height = figure_height, pointsize = 12, res = fiure_res , units = "px")    
    split.screen(c(2,1))
    screen(1)
    boxplot(input_data, main = raw_data_boxplot_title, las=2)
    screen(2)
    boxplot(log2_cent_data, main = centered_data_boxplot_title, las=2)
    dev.off()
  }
 
}
