MGRAST_dendrograms <<- function(
                                file_in,
                                file_out_column =  "col_clust",
                                file_out_row    =  "row_clust",
                                dist_method           = "euclidean", # ("euclidean", "maximum", "manhattan", "canberra", "binary", "minkowski")
                                clust_method          = "ward",  # ("ward", "single", "complete", "average", "mcquitty", "median", "centroid")
                                
                                produce_figures       = FALSE,
                                col_dendrogram_width  = 950,
                                col_dendrogram_height = 500,
                                row_dendrogram_width  = 950,
                                row_dendrogram_height = 500,
                                output_files_prefix   = "my_dendrograms"
                                )
  
{

# load packages
  #suppressPackageStartupMessages(library(matlab))      
  suppressPackageStartupMessages(library(ecodist))
  #suppressPackageStartupMessages(library(Cairo))
  #suppressPackageStartupMessages(library(gplots))
  
    
# define sub functions
  func_usage <- function()
    {
      writeLines("
     You supplied no arguments

     DESCRIPTION: (MGRAST_dendrograms):
     This script will perform dendrogram analysis (x and y) of input data
     using the selected distance/dissimilarity  metric and the selected
     clustering method.
     Two ouputs, for sorting the data by row and/or column

     USAGE: MGRAST_dendrograms(
                               file_in = \"file\",               # input data file, no default,            
                               file_out_column = \"col_clust\",  # output column clustering indeces, default = \"col_clust\"
                               file_out_row = \"row_clust\",     # output row clustering indeces,    default = \"row_clust\"
                               dist_method = (choose from one of the following options)
                                          # distance/dissimilarity metric, default = \"bray-curtis\"

                                          \"euclidean\" | \"maximum\"     | \"canberra\"    |
                                          \"binary\"    | \"minkowski\"   | \"bray-curtis\" |
                                          \"jacccard\"  | \"mahalanobis\" | \"sorensen\"    |
                                          \"difference\"

                               clust_method = (choose one of the following options)
                                           # clustering  method, default = \"ward\"

                                          \"ward\"      | \"single\"      | \"complete\" |
                                          \"mcquitty\"  | \"median\"      | \"centroid\" |
                                          \"average\" 

                               )\n"
                 )
      stop("MGRAST_dendrograms stopped\n\n")
    }
  
  find_dist <- function(my_data, dist_method)
    {
      switch(
             dist_method,
             "euclidean" = dist(my_data, method = "euclidean"), 
             "maximum" = dist(my_data, method = "maximum"),
             "manhattan" = dist(my_data, method = "manhattan"),
             "canberra" = dist(my_data, method = "canberra"),
             "binary" = dist(my_data, method = "binary"),
             "minkowski" = dist(my_data, method = "minkowski"),
             "bray-curtis" = distance(my_data, method = "bray-curtis"),
             "jaccard" = distance(my_data, method = "jaccard"),
             "mahalanobis" = distance(my_data, method = "mahalanobis"),
             "sorensen" = distance(my_data, method = "sorensen"),
             "difference" = distance(my_data, method = "difference")
             # unifrac
             # weighted_unifrac

             # distance methods with {stats}dist: dist(x, method = "euclidean", diag = FALSE, upper = FALSE, p = 2)
             #      euclidean maximum manhattan canberra binary minkowski

             # distance methods with {ecodist}distance: distance(x, method = "euclidean")
             #      euclidean bray-curtis manhattan mahalanobis jaccard "simple difference" sorensen

             )
    }

###### Supply usage if the function is called without args  
  if ( nargs() == 0 )
    {
      func_usage()
    }
  
###### import the data file to be processed    
  {  
    input_object <- data.matrix(read.table(file_in, row.names=1, header=TRUE, sep="\t", comment.char="", quote=""))
  }
  
###### load the neccessary packages
  if (produce_figures==TRUE)
    {
      suppressPackageStartupMessages(library(Cairo)) # (### indicates commented out to prevent production of the figure)
    }
##### by default, hclust(dist(object)) will produce a row dendrogram of the object 
##### get the element counts for the imported object (this will be for the row dendrogram)
##### and for the 90 degree rotated version (for the column dendrogram)   
  og_row_count <- (dim(input_object)[1]) # number rows
  og_row_names <- dimnames(input_object)[[1]]
  og_col_count <- (dim(input_object)[2]) # number columns
  og_col_names <- dimnames(input_object)[[2]]
  
  input_object_rot_90 <- matrix(0,og_col_count,og_row_count)
  
  for (i in 1:og_col_count)
    { # rotate data by 90 degrees -- rotated data will be used to create the column dendrogram
      og_col = input_object[,i]
      col_to_row = (og_col[og_row_count:1])
      input_object_rot_90[i,] <- col_to_row
    } 

  dimnames(input_object_rot_90)[[1]] <- og_col_names # col names become row names - ordering of names stays the same
  dimnames(input_object_rot_90)[[2]] <- (og_row_names[og_row_count:1]) # row names become col names - order has to be reversed to be correct 

  input_object_row_cluster <- hclust(find_dist(input_object, dist_method), method = clust_method)
  input_object_clustered_row_order <- input_object_row_cluster$order

  if (produce_figures==TRUE)
    {
      row_dendrogram_filename = paste(output_files_prefix, ".dist-", dist_method, "_clust-", clust_method, ".row_dendrogram.png")
      row_dendrogram_filename = gsub(" ", "", row_dendrogram_filename)
      CairoPNG(row_dendrogram_filename, width = row_dendrogram_width , height = row_dendrogram_height , units = "px")
      plot(input_object_row_cluster, labels = input_object_row_cluster$labels, hang = -1, ann = FALSE, yaxs = "i") # THIS WORKS
      dev.off()
    }
  row_labels = matrix(0,1,(dim(matrix(input_object_row_cluster$labels))[1]))

  for(i in 1:(dim(matrix(input_object_row_cluster$labels))[1]))
    {
      row_labels[i] = input_object_row_cluster$labels[input_object_row_cluster$order[i]]
    }

  input_object_col_cluster <- hclust(find_dist(input_object_rot_90, dist_method), method = clust_method)
  input_object_clustered_col_order <- input_object_col_cluster$order

  if (produce_figures==TRUE)
    {
      col_dendrogram_filename = paste(output_files_prefix, ".dist-", dist_method, "_clust-", clust_method, ".column_dendrogram.png")
      col_dendrogram_filename = gsub(" ", "", col_dendrogram_filename)
      CairoPNG(col_dendrogram_filename, width = col_dendrogram_width , height = col_dendrogram_height , units = "px")
      plot(input_object_col_cluster, labels = input_object_col_cluster$labels, hang = -1, ann = FALSE, yaxs = "i")
      dev.off()
    }
  col_labels = matrix(0,1,(dim(matrix(input_object_col_cluster$labels))[1]))

  for(i in 1:(dim(matrix(input_object_col_cluster$labels))[1]))
    {
      col_labels[i] = input_object_col_cluster$labels[input_object_col_cluster$order[i]]
    }
  
  # create the text files with the parameters to draw the dendrograms with something other than R
  cat(rev(input_object_col_cluster$order), sep=",", fill=FALSE, file = file_out_column)
  write("", file = file_out_column, append=TRUE)
  cat(rev(col_labels), sep=",", fill=FALSE, file = file_out_column, append=TRUE)
  write("", file = file_out_column, append=TRUE)
  merge_height_col = cbind(input_object_col_cluster$merge, matrix(input_object_col_cluster$height))
  write.table(merge_height_col, file = file_out_column, sep = "\t", append = TRUE, col.names = FALSE, row.names = FALSE)

  cat(input_object_row_cluster$order, sep=",", fill=FALSE, file = file_out_row)
  write("", file = file_out_row, append=TRUE)
  cat(row_labels, sep=",", fill=FALSE, file = file_out_row, append = TRUE)
  write("", file = file_out_row, append=TRUE)
  merge_height_row= cbind(input_object_row_cluster$merge, matrix(input_object_row_cluster$height))
  write.table(merge_height_row, file = file_out_row, sep = "\t", append = TRUE, col.names = FALSE, row.names = FALSE)

  ## # cleanup
  ## rm(
  ##    input_object,
  ##    input_object_rot_90,
  ##    input_object_col_cluster,
  ##    input_object_row_cluster,
  ##    input_object_clustered_row_order,
  ##    input_object_clustered_col_order
  ##    )
  
}
