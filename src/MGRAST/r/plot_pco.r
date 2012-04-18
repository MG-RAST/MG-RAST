MGRAST_plot_pco <- function(
                            file_in,
                            file_out = "my_PCoA",
                            dist_method = "bray-curtis",
                            headers = 0
                            )


  

{

  # load packages
  suppressPackageStartupMessages(library(matlab))      
  suppressPackageStartupMessages(library(ecodist))
  #suppressPackageStartupMessages(library(Cairo))
  #suppressPackageStartupMessages(library(gplots))

  # define sub functions
  func_usage <- function() {
    writeLines("
     You supplied no arguments

     DESCRIPTION: (MGRAST_plot_pco.r):
     This script will perform a PCoA analysis on the inputdata
     using the selected distance metric.  Output is a single file
     that has the normalized eigenvalues (top n lines) and eigenvectors
     (bottom n x m matris, n lines) where n is the number of variables (e.g.
     subsystems), and m the number of samples.

     USAGE: MGRAST_plot_pca(
                            file_in = \"file\",                                        # input data file, no default,            
                            file_out = \"my_PCoA\",                                    # output file,     default = \"my_PCoA\"  
                            dist_method = (choose from one of the following options) # distance/dissimilarity metric,
                                                                                     # default = \"bray-curtis\"

                                          \"euclidean\" | \"maximum\"     | \"canberra\"    |
                                          \"binary\"    | \"minkowski\"   | \"bray-curtis\" |
                                          \"jacccard\"  | \"mahalanobis\" | \"sorensen\"    |
                                          \"difference\"

                            headers = 0 | 1                                          # default = 0, print headers in output_file 
                            )\n"
               )
    stop("MGRAST_plot_pco stopped\n\n")
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


  # stop and give the usage if the proper number of arguments is not given
  if ( nargs() == 0 ){
    func_usage()
  }

  # load data
  {                                                                                            
    my_data <<- flipud(rot90(data.matrix(read.table(file_in, row.names=1, header=TRUE, sep="\t", comment.char="", quote=""))))
  }
  
  # calculate distance matrix
  dist_matrix <<- find_dist(my_data, dist_method)
  
  # perform the pco
  my_pco <<- pco(dist_matrix)

  # scale eigen values from 0 to 1, and label them
  eigen_values <<- my_pco$values
  scaled_eigen_values <<- (eigen_values/sum(eigen_values))
  for (i in (1:dim(as.matrix(scaled_eigen_values))[1])) {names(scaled_eigen_values)[i]<<-gsub(" ", "", paste("PCO", i))}
  scaled_eigen_values <<- data.matrix(scaled_eigen_values)
  #for (i in (1:dim(as.matrix(scaled_ev))[1])) dimnames(scaled_ev)[i]<<-gsub(" ", "", paste("PCO", i))

  # label the eigen vectors
  eigen_vectors <<- data.matrix(my_pco$vectors) 
  dimnames(eigen_vectors)[[1]] <<- dimnames(my_data)[[1]]

  # write eigen values and then eigen vectors to file_out
  if ( headers == 1 ){
    write(file = file_out, paste("# file_in    :", file_in,
            "\n# dist_method:", dist_method,
            "\n#________________________________",
            "\n# EIGEN VALUES (scaled 0 to 1) >",
            "\n#________________________________"),
          append=FALSE)
    write.table(scaled_eigen_values,     file=file_out, col.names=FALSE, row.names=TRUE, append = TRUE, sep="\t")
  }else{
    write.table(scaled_eigen_values,     file=file_out, col.names=FALSE, row.names=TRUE, append = FALSE, sep="\t")
  }
  
  if ( headers == 1 ){
    write(file = file_out, paste("#________________________________",
            "\n# EIGEN VECTORS >",
            "\n#________________________________"),
          append=TRUE)
  }

  write.table(eigen_vectors, file=file_out, col.names=FALSE, row.names=TRUE, append = TRUE, sep="\t")
  
}
