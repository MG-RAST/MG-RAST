# data_in is a comma separted list of data points
# groups_in is a comma separted list of group indeces for the points in data_in

MGRAST_do_stats <<- function (data_file,
                              groups_file,
                              data_type = c("raw", "normalized"),
                              sig_test = c(
                                "t-test-paired", "Wilcoxon-paired",
                                "t-test-un-paired", "Mann-Whitney_un-paired-Wilcoxon",
                                "ANOVA-one-way", "Kruskal-Wallis"
                                ),
                              file_out)
  
{

  

  ### SUB TO WRITE OUTPUT
  write_log <<- function (sig_test, data_type){
    write(paste("test is     : ", sig_test),    file = "do_stats.log")
    write(paste("data-type   : ", data_type),   file = "do_stats.log", append = TRUE)
    write(paste("num-samples : ", num_samples), file = "do_stats.log", append = TRUE)
    write(paste("num-groups  : ", num_groups),  file = "do_stats.log", append = TRUE)
  }
  

  
  ### SUB TO PREP DATA FOR TWO GROUP ANALYSES
  prep_two_groups <<- function(row_data){
    group_1 = levels(row_data[,2])[1]
    group_2 = levels(row_data[,2])[2]
    group_1_size = 0
    group_2_size = 0
    for (i in 1:as.matrix(dim(row_data)[1])){
      if(identical(as.character(row_data[i,2]), as.character(group_1))){
        group_1_size = group_1_size + 1
      }
      if(identical(as.character(row_data[i,2]), as.character(group_2))){
        group_2_size = group_2_size + 1
      }
    }
    group_1_data <<- matrix(,group_1_size,1)
    group_2_data <<- matrix(,group_2_size,1)
    group_1_index = 0
    group_2_index = 0
    for (i in 1:as.matrix(dim(row_data)[1])){
      if (identical(as.character(row_data[i,2]), as.character(group_1))){
        group_1_index = group_1_index + 1
        group_1_data[group_1_index,1] <<- row_data[i,1]
      }
      if (identical(as.character(row_data[i,2]), as.character(group_2))){
        group_2_index = group_2_index + 1
        group_2_data[group_2_index,1] <<- row_data[i,1]
      }
    }
  }


  
  ### ### MAIN SCRIPT STARTS HERE ### ###
  
  ### TEST TO MAKE SURE ALL OF THE ARGUMENTS ARE SUPPLIED
  #if()

  # LOAD NECESSARY PACKAGES
  library(stats)
  library(nlme)

  ### IMPORT AND FORMAT THE DATA ###
  all_data = data.frame(read.table(data_file, row.names=1, header=TRUE, sep="\t", comment.char="", quote=""))
  groups = data.matrix(scan(file = groups_file, what = "character", sep = "\t", quiet=TRUE))
  num_samples = dim(all_data)[2]
  num_rows = dim(all_data)[1]
  num_groups <<- nlevels(as.factor(groups[,1]))    # <----- Rats
  group_names <<- matrix(levels(as.factor(groups[,1])))

  # CREATE OUTPUT TABLE AND GIVE IT APPROPRIATE HEADERS
  output_table <<- data.frame(matrix(0, num_rows, num_groups+2))
  row.names(output_table) <<- row.names(all_data)
  names(output_table) <<- c(paste("group_(", levels(as.factor(groups[,1])),")_stddev",sep =""),
                            paste(sig_test, "_stat",sep=""),
                            paste(sig_test, "_p_value",sep="")
                            )
  
  ### PERFORM THE ANALYSES
  for (my_row in 1:num_rows){
    
    numeric_row_data <<- as.numeric(all_data[my_row,])
    factor_row_groups <<- as.character(groups[,1]) # is ok here
    row_data <<- cbind(numeric_row_data, factor_row_groups)
    row_data <<- data.frame(row_data)
    row_data[,1] <<- numeric_row_data # some values get changed if you don;t reload them here
    row_data[,2] <<- as.factor(row_data[,2])
    names(row_data)<<-c("values","ind")
    
    for (group in 1:num_groups){
      
      group_ind <<- levels(row_data[,2])[group]
      
      ### CALCULATE THE STANDARD DEVIATION FOR EACH GROUP  
      num_samples_in_group <<- 0
      for(sample in 1:num_samples){
        if(identical(((matrix(row_data[sample,2]))[1,1]), group_ind)){
          if (num_samples_in_group==0){
            group_sample_counts <<- row_data[sample,1]
            num_samples_in_group <<- num_samples_in_group + 1
          }else{
            group_sample_counts <<- c(group_sample_counts, row_data[sample,1])
            num_samples_in_group <<- num_samples_in_group + 1
          }
        }
      }
      output_table[my_row, group] <<- as.real(sd(group_sample_counts))
    }

    if(identical(sig_test, "t-test-un-paired")){   # <-- new
      prep_two_groups(row_data)
      ttest_unpaired_output = t.test(group_1_data, group_2_data)
      t_unpaired_stat_value = as.real(ttest_unpaired_output["statistic"])
      t_unpaired_p_value = as.real(ttest_unpaired_output["p.value"])
      output_table[my_row, num_groups+1] <<- t_unpaired_stat_value
      output_table[my_row, num_groups+2] <<- t_unpaired_p_value 
    }
        
    else if(identical(sig_test, "t-test-paired")){   # <-- new
      prep_two_groups(row_data)
      ttest_paired_output = t.test(group_1_data, group_2_data, paired = TRUE)
      t_paired_stat_value = as.real(ttest_paired_output["statistic"])
      t_paired_p_value = as.real(ttest_paired_output["p.value"])
      
      output_table[my_row, num_groups+1] <<- t_paired_stat_value
      output_table[my_row, num_groups+2] <<- t_paired_p_value
    }

    else if (identical(sig_test, "ANOVA-one-way")){
      anova_output = anova(aov(values~ind, data=row_data)) 
      anova_F = anova_output["F value"]
      F_value = as.real(anova_F[1,1]) 
      anova_p = anova_output["Pr(>F)"]
      anova_p_value = as.real(anova_p[1,1])
      output_table[my_row, num_groups+1] <<- F_value 
      output_table[my_row, num_groups+2] <<- anova_p_value
    }
    
    else if (identical(sig_test, "Mann-Whitney_un-paired-Wilcoxon")){
      prep_two_groups(row_data)
      MWhitney_output = wilcox.test(group_1_data, group_2_data, exact=TRUE) # x -> s in text
      MWhitney_stat_value = as.real(MWhitney_output["statistic"])
      MWhitney_p_value = as.real(MWhitney_output["p.value"])
      output_table[my_row, num_groups+1] <<- MWhitney_stat_value
      output_table[my_row, num_groups+2] <<- MWhitney_p_value
    }

    else if (identical(sig_test, "Wilcoxon-paired")){   # <-- new
      prep_two_groups(row_data)
      wilcox_output = wilcox.test(group_1_data, group_2_data, exact=TRUE, paired=TRUE) # x -> s in text
      wilcox_stat_value = as.real(wilcox_output["statistic"])
      wilcox_p_value = as.real(wilcox_output["p.value"])
      output_table[my_row, num_groups+1] <<- wilcox_stat_value
      output_table[my_row, num_groups+2] <<- wilcox_p_value
    }
    
    else if (identical(sig_test, "Kruskal-Wallis")){
      kruskal_output = kruskal.test(row_data[,1], row_data[,2])
      kruskal_K_value = as.real(kruskal_output["statistic"])
      kruskal_p_value = as.real(kruskal_output["p.value"])
      output_table[my_row, num_groups+1] <<- kruskal_K_value
      output_table[my_row, num_groups+2] <<- kruskal_p_value
    }
    
    else{
      stop("no significance test was chosen")
    }
    
    write.table(output_table, file = file_out, sep = "\t", col.names=NA, row.names = TRUE)
    
  }
  
}
