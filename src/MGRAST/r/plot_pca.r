MGRAST_plot_pca <<- function(file_in,
                             file_out = "my_pca",
                             
                             num_PCs = 2,

                             produce_fig = FALSE,
                             PC1="PC1",
                             PC2="PC2",
                             
                             image_out = "my_pca",
                             image_title = image_out,
                             figure_width = 950,
                             figure_height = 950,
                             points_color = "red",  #c ("color1","color2", ... ,"color_n")  e.g. c("red","red","red")
                             figure_res = NA,
                             lab_cex= 1,
                             axis_cex = 1,
                             points_text_cex = .8)

  
{

                                                      
  suppressPackageStartupMessages(library(pcaMethods))                                               # load the neccessary packages (suppress messages)
  
 
  {                                                                                                 # sub to import the input_file
    input_object = data.matrix(read.table(file_in, row.names=1, header=TRUE, sep="\t", comment.char="", quote=""))
  }  
 
  number_entries = (dim(input_object)[1])                                                           # get dimensions of input object
  number_samples = (dim(input_object)[2])
  
  my_pcaRes <<- pca(input_object, nPcs = num_PCs)                                                   # Run pca and create pcaRes object
  
  # if (produce_fig == TRUE){                                                                         # option to produce figure
  # 
  #   suppressPackageStartupMessages(library(Cairo))
  #   
  #   CairoPNG(image_out, width = figure_width, height = figure_height, pointsize = 12, res = figure_res , units = "px")
  # 
  #   plot(my_pcaRes@loadings[,PC1],
  #        my_pcaRes@loadings[,PC2],    
  #        cex.axis = axis_cex,
  #        cex.lab = lab_cex,
  #        main = image_title,
  #        type = "p",
  #        col = points_color,
  #        xlab = paste(PC1, "R^2 =", round(my_pcaRes@R2[PC1], 4)),
  #        ylab = paste(PC2, "R^2 =", round(my_pcaRes@R2[PC2], 4))
  #        )
  # 
  #   if (points_color != 0){ 
  #     points(my_pcaRes@loadings[,PC1], my_pcaRes@loadings[,PC2], col = points_color, pch=19, cex=2 )
  #     # color in the points if the points_color option has a value other than NA
  #     # pch, integer values that indicate different point types (19 is a filled circle)
  #   }
  #   
  #   text(my_pcaRes@loadings[,PC1], my_pcaRes@loadings[,PC2], labels=rownames(my_pcaRes@loadings), cex = points_text_cex)
  # } 
  
  write.table(my_pcaRes@R2,        file=file_out, sep="\t", col.names=FALSE, row.names=TRUE, append = FALSE)
  write.table(loadings(my_pcaRes), file=file_out, sep="\t", col.names=FALSE, row.names=TRUE, append = TRUE)
  
}

#write.table(loadings(my_pcaRes), file=gsub(" ", "_", paste(files_out_prefix, "LOADINGS_matrix.txt")),
#            sep="\t", col.names = NA, row.names = TRUE)
#write.table(scores(my_pcaRes), file=gsub(" ", "_", paste(files_out_prefix, "SCORES_matrix.txt")),
#            sep="\t", col.names = NA, row.names = TRUE)

