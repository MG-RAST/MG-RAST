MGRAST_suggest_test <<- function (data_file, groups_file, data_type=c("raw", "normalized"), paired = FALSE, file_out="suggest_stat_test.out")
  {
    


    ### SUB TO WRITE OUTPUT
    write_out = function (sig_test, data_type, paired, num_samples, num_groups, file_out){
      #print("got here")
      write(paste("suggested test is =", sig_test,    sep = "\t"), file = file_out)
      write(paste("data-type         =", data_type,   sep = "\t"), file = file_out, append = TRUE)
      write(paste("paired            =", paired,      sep = "\t"), file = file_out, append = TRUE)
      write(paste("num-samples       =", num_samples, sep = "\t"), file = file_out, append = TRUE)
      write(paste("num-groups        =", num_groups,  sep = "\t"), file = file_out, append = TRUE)
    }
    

    
    my_data = data.matrix(read.table(data_file, row.names=1, header=TRUE, sep="\t", comment.char="", quote=""))
    my_groups = data.matrix(scan(file = groups_file, what = "character", sep = "\t", quiet=TRUE))
    num_groups = nlevels(as.factor(my_groups))
    num_samples = dim(my_data)[2]
    
    sig_test = NA
    
    ### CHECK DATA FOR MINIMUM STATISTICAL REQUIREMENTS
    if(num_groups==1|num_samples<=2|num_samples!=dim(my_data)[1]){
      write("Minimum analysis requirements not met - no test could be selected:\n", file = file_out)
      write(paste("data_type   =", data_type, sep = "\t"  ), file = file_out, append = TRUE)
      write(paste("paired      =", paired, sep = "\t"     ), file = file_out, append = TRUE)
      write(paste("num_samples =", num_samples, sep = "\t"), file = file_out, append = TRUE)
      write(paste("num_groups  =", num_groups, sep = "\t" ), file = file_out, append = TRUE)
      write(("\nSingle sample analyses are not supported.
The minimum analysis requirements are:
     (1) at least two groups of samples(metagenomes)
     (2) at least one group with two or more samples."
             ),                               file = "suggest_stat_test.out", append = TRUE)
    }


  
     ### CHOOSE MOST APPROPRIATE TEST
    if (data_type=="normalized"){
      if(num_groups==2){
        if(paired==TRUE){
          sig_test = "t-test-paired" # t_test
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out)
        }else{
          sig_test = "t-test-un-paired" # t_test
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out)
        }
      }else if (num_groups>2){
        if(paired==TRUE){
          sig_test = "repeat-measures-ANOVA_(not-yet-supported)" # ANOVA
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out)
        }else{
          sig_test = "ANOVA-one-way" # ANOVA
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out)
        } 
      }
    }else if (data_type=="raw"){
      if (num_groups==2){
        if(paired==TRUE){
          sig_test = "Wilcoxon-paired" # wilcoxon
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out)
        }else{
          sig_test = "Mann-Whitney_un-paired_Wilcoxon" # wilcoxon
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out)
        }
      }else if (num_groups>2){
        if(paired==TRUE){
          sig_test = "Friedman-test_(not-yet-supported)" # kruskal_wallis
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out)
        }else{
          sig_test = "Kruskal-Wallis" # kruskal_wallis
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out)
        }
      }
    }else{
      sig_test = "NONE___try_again"
      write_out(data_type, num_samples, num_groups, sig_test, file_out)
    # stop("No test could be selected")
    }
  }



