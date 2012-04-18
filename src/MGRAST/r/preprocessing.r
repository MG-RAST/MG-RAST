MGRAST_preprocessing <<- function(file_in,     # name of the input file (tab delimited text with the raw counts)
                                             file_out = "preprocessed_data",    # name of the output data file (tab delimited text of preprocessed data)

                                             produce_fig = FALSE,     # boolean - to produce a figure (TRUE) or not (FALSE)
                                             image_out = "my_boxplots",   # name of the output image (the boxplot figure)
                                             raw_data_boxplot_title      = "raw data",   # title for the top (raw data boxplot)
                                             centered_data_boxplot_title = "log2(x+1) & centered per sample, scaled 0 to 1 over all samples", # title for the lower (preprocesed data) boxplot
                                             figure_width                = 950,                      # usually pixels, inches if eps is selected; png is default
                                             figure_height               = 1000,                     # usually pixels, inches if eps is selected; png is default
                                             figure_res                  = NA                       # usually pixels, inches if eps is selected; png is default      
                                             ) 

{

###### sub to import the input_file
#import_data <- function(file_name)
  {
    input_data = data.matrix(read.table(file_in, row.names=1, header=TRUE, sep="\t", comment.char="", quote=""))
  }
###### replace NA's with 0
  input_data[ is.na(input_data) ]<-0

###### get the diensions of the input object  
  number_entries = (dim(input_data)[1]) # number rows
  number_samples = (dim(input_data)[2]) # number columns

###### perform log transformation  
  log2_data = log2(input_data + 1)

###### create object to store data that are log transformed and centered  
  log2_cent_data <<- matrix(0, number_entries, number_samples)

###### pull column and row names from the input_data   
  dimnames(log2_cent_data)[[2]] <<- dimnames(input_data)[[2]] # colnames #edited 6-15-10
  dimnames(log2_cent_data)[[1]] <<- dimnames(input_data)[[1]] # rownames #edited 6-15-10

###### center data from each sample (column)  
  for (i in 1:number_samples){ 
    sample = log2_data[,i]
    mean_sample = mean(sample) 
    stdev_sample = sd(sample)
    for (j in 1:number_entries){
      log2_cent_data[j,i] <<- ((log2_data[j,i] - mean_sample)/stdev_sample)
    } 
  }


###### norm values from 0 to 1  
  min_value = min(log2_cent_data)
  for (i in 1:number_samples){ 
    for (j in 1:number_entries){
      log2_cent_data[j,i] <<- (log2_cent_data[j,i] + abs(min_value))
    } 
  }
  max_value= max(log2_cent_data)
  for (i in 1:number_samples){ 
    for (j in 1:number_entries){
      if (log2_cent_data[j,i] == 0){
      }else{
        log2_cent_data[j,i] <<- ((log2_cent_data[j,i]/max_value))
      } 
    }
  }


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
