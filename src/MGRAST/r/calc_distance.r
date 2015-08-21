MGRAST_distance <- function(
                            file_in,
                            file_out = "my_PCoA",
                            dist_method = "bray-curtis"
                            )

{
  # load packages
  suppressPackageStartupMessages(library(matlab))      
  suppressPackageStartupMessages(library(ecodist))

  # define sub functions
  func_usage <- function() {
    writeLines("
     You supplied no arguments

     DESCRIPTION: (calc_distance.r):
     This script will compute the given distance metric.

     USAGE: MGRAST_distance(
                            file_in = \"file\",                                      # input data file, no default
                            file_out = \"my_distance\",                              # output file,    default = \"my_distance\"
                            dist_method = \"bray-curtis\"                            # (string)  distance/dissimilarity metric,
                                          (choose from one of the following options)
                                          \"euclidean\" | \"maximum\"     | \"canberra\"    |
                                          \"binary\"    | \"minkowski\"   | \"bray-curtis\" |
                                          \"jacccard\"  | \"mahalanobis\" | \"sorensen\"    |
                                          \"difference\"| \"manhattan\"
                            )\n"
               )
    stop("MGRAST_distance stopped\n\n")
  }
  
  find_dist <- function(my_data, dist_method)
    {
      switch(dist_method,
             "euclidean" = dist(my_data, method = "euclidean"), 
             "maximum" = dist(my_data, method = "maximum"),
             "manhattan" = dist(my_data, method = "manhattan"),
             "canberra" = dist(my_data, method = "canberra"),
             "binary" = dist(my_data, method = "binary"),
             "minkowski" = dist(my_data, method = "minkowski"),
             "bray-curtis" = bcdist(my_data),
             "jaccard" = distance(my_data, method = "jaccard"),
             "mahalanobis" = distance(my_data, method = "mahalanobis"),
             "sorensen" = distance(my_data, method = "sorensen"),
             "difference" = distance(my_data, method = "difference")
             )
    }

  # stop and give the usage if the proper number of arguments is not given
  if ( nargs() == 0 ){
    func_usage()
  }

  # input data as an appropriate R object
  my_data <- flipud(rot90(data.matrix(read.table(file_in, row.names=1, check.names=FALSE, header=TRUE, sep="\t", comment.char="", quote=""))))
  
  # substitute 0 for NA's if they exist in the data
  data_is_na <- ( is.na(my_data) )
  my_data[data_is_na==TRUE] <- 0
   
  # calculate distance matrix and write the results to file
  dist_matrix <- find_dist(my_data, dist_method)
  write.table(x=data.matrix(dist_matrix), file=file_out, col.names=NA, row.names=TRUE, append = FALSE, sep="\t", quote = FALSE, eol="\n")
  
}
