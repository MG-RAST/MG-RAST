MGRAST_suggest_test <<- function (data_file, groups_file, data_type=c("raw", "normalized"), paired = FALSE, file_out)
  {
    


    ### SUB TO WRITE OUTPUT
    write_out = function (sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes){
      #print("got here")
      write(sig_test, file = file_out)
      write(paste("data-type         =", data_type,   sep = "\t"), file = file_out, append = TRUE)
      write(paste("paired            =", paired,      sep = "\t"), file = file_out, append = TRUE)
      write(paste("num-samples       =", num_samples, sep = "\t"), file = file_out, append = TRUE)
      write(paste("num-groups        =", num_groups,  sep = "\t"), file = file_out, append = TRUE)
      write(paste("test_notes        =", test_notes,  sep = "\t"), file = file_out, append = TRUE)
    }
    

    
    my_data = data.matrix(read.table(data_file, row.names=1, header=TRUE, sep="\t", comment.char="", quote=""))
    my_groups <<- data.matrix(scan(file = groups_file, what = "character", sep = "\t", quiet=TRUE))
    num_groups = nlevels(as.factor(my_groups))
    num_samples = dim(my_data)[2]
    
    sig_test = NA
    test_notes = "none"
    
    ### CHECK DATA FOR MINIMUM STATISTICAL REQUIREMENTS
    if(num_groups==1|num_samples<=2|num_samples!=dim(my_data)[1]){
      write("Minimum analysis requirements not met - no test could be selected:\n", file = file_out)
      write(paste("data_type   =", data_type, sep = "\t"  ), file = file_out, append = TRUE)
      write(paste("paired      =", paired, sep = "\t"     ), file = file_out, append = TRUE)
      write(paste("num_samples =", num_samples, sep = "\t"), file = file_out, append = TRUE)
      write(paste("num_groups  =", num_groups, sep = "\t" ), file = file_out, append = TRUE)
      write(paste("test_notes  =", test_notes,  sep = "\t"), file = file_out, append = TRUE)
      write(("\nSingle sample analyses are not supported.
The minimum analysis requirements are:
     (1) at least two groups of samples(metagenomes)
     (2) at least one group with two or more samples."
             ),                               file = file_out, append = TRUE)
    }



    special_case <<- 0
    group_1_size <<- 0
    group_2_size <<- 0
    ### HANDLE SPECIAL CASE - two groups, one of which has just a single measure
    test_two_groups<<-function(my_groups){
      #if(num_groups==2){
      group_names <<- levels(as.factor(my_groups))
      group_1 <<- group_names[1]
      group_2 <<- group_names[2]
      group_1_size <<- 0
      group_2_size <<- 0
      for (i in my_groups){
        #print(paste("i: ", i))
        #print(paste("my groups i: ", my_groups[i]))
        #if(identical(as.character(my_groups[i]), as.character(group_1))){
        if(identical(as.character(i), as.character(group_1))){
          group_1_size <<- group_1_size + 1
          #print(paste("group_1_size", group_1_size))
        }
        #if(identical(as.character(my_groups[i]), as.character(group_2))){
        if(identical(as.character(i), as.character(group_2))){
          group_2_size <<- group_2_size + 1
          #print(paste("group_2_size", group_2_size))
          #print(paste("group_2_size", group_2_size))
        }
      }
      if(group_1_size==1|group_2_size==1){
        special_case <<- 1
        #print(paste("special_case", special_case))
      }
      #}
      #return(list(group_1_size, group_2_size, special_case))
    }

    #print(paste("num_groups", num_groups))
    #print(paste("group_1_size", group_1_size))
    #print(paste("group_2_size", group_1_size))
    #print(paste("special_case", special_case))


    ### CHOOSE MOST APPROPRIATE TEST
    if (data_type=="normalized"){
      if(num_groups==2){
        #(group_1_size, group_2_size) <<- test_two_groups(my_groups)
        test_two_groups(my_groups)
        if(paired==TRUE){
          if(special_case==0){
            sig_test = "t-test-paired" # t_test
            # test_notes
            write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
          }else{
            sig_test = "ANOVA_repeat_measures (not yet supported: you could try ANOVA-one-way, note that it assumes independent measures)"
            test_notes = "One of the two groups has just a single measure.  t-test cannot be used because it requires at least 2 measures per group.  The suggested ANOVA \"can\" be used, but statistical power is likely to be very low." 
            write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
          }          
        }else{
          if(special_case==0){
            sig_test = "t-test-un-paired" # t_test
            # test_notes
            write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
          }else{
            sig_test = "ANOVA-one-way"
            test_notes = "One of the two groups has just a single measure.  t-test cannot be used because it requires at least 2 measures per group.  The suggested ANOVA \"can\" be used, but statistical power is likely to be very low." 
            write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
          }
        }
      }else if (num_groups>2){
        if(paired==TRUE){
          sig_test = "ANOVA-repeat-measures" # ANOVA
          test_notes = "not currently supported - you may be able to try ANOVA-one-way, note that it assumes independent measures"
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
        }else{
          sig_test = "ANOVA-one-way" # ANOVA
          # test_notes
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
        } 
      }        
    }else if (data_type=="raw"){
      if (num_groups==2){
        test_two_groups(my_groups)
        if(paired==TRUE){
          if(special_case==0){
            sig_test = "Wilcoxon-paired" # wilcoxon
            # test_notes =
            write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
          }else{
            sig_test = "Wilcoxon-paired" # wilcoxon
            test_notes = "one of the two groups has just a single sample; statistical power is likley to be very low"
            write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)  
          }
        
        }else{
          if(special_case==0){
            sig_test = "Mann-Whitney_un-paired_Wilcoxon" # wilcoxon
            test_notes = "this test is also known as the Mann-Whitney U test, the Mann-Whitney_Wilcoxon test, or the Wilcoxon rank-sum test"
            write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
          }else{
            sig_test = "Mann-Whitney_un-paired_Wilcoxon" # wilcoxon
            test_notes = "one of the two groups has just a single sample; statistical power is likley to be very low"
            write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
          }
        }
  
      }else if (num_groups>2){
        if(paired==TRUE){
          sig_test = "Friedman-test" # kruskal_wallis
          test_notes = "not-yet-supported: you could try an ANOVA-one-way on the normalized data, note that ANOVA-one-way assumes independent measures" 
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
        }else{
          sig_test = "Kruskal-Wallis" # kruskal_wallis
          write_out(sig_test, data_type, paired, num_samples, num_groups, file_out, test_notes)
        }
      }
    }else{
      sig_test = "NONE"
      test_notes = "no test could be found for the selected data - please try again"
      write_out(data_type, num_samples, num_groups, sig_test, file_out, test_notes)
      # stop("No test could be selected")
    }
  }



