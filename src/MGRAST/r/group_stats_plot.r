group_stats_plot <- function(
                         file_in = "",
                         file_out = "",
                         figure_out = NULL, # give a name and it will produce a file
                         stat_test = "Kruskal-Wallis", # (an matR stat test)
                         order_by = NULL, # column to order by - can be integer column index (1 based) or column header -- paste(stat_test, "::fdr", sep="")
                         order_decreasing = TRUE,
                         my_n = 5, # number of categories to plot
                         group_lines = 0,           # if groupings are in the file
                         group_line_to_process = 0, # if groupings are in the file
                         my_grouping = NA           # to supply groupings with a list                 
                         )
{

# Check to make sure either that groupings are in the data file, or that a groupings argument
# has been specified  
# Make sure the required pacakges are loaded
  require(matR)
  require(matlab)
  # require(ggplot2)

######################### DEFINE LOCAL SUB FUNCTIONS ####################### 
############################################################################
# Color methods https://stat.ethz.ch/pipermail/r-help/2002-May/022037.html
############################################################################
# The inverse function to col2rgb()
  col.wheel <- function(num_col, my_cex=0.75) {
    cols <- rainbow(num_col)
    col_names <- vector(mode="list", length=num_col) 
    for (i in 1:num_col){
      col_names[i] <- getColorTable(cols[i])
    }
# pie(rep(1, length(cols)), labels=col_names, col=cols, cex=my_cex) }
    cols
  }

# The inverse function to col2rgb()
  rgb2col <- function(rgb) {
    rgb <- as.integer(rgb)
    class(rgb) <- "hexmode"
    rgb <- as.character(rgb)
    rgb <- matrix(rgb, nrow=3)
    paste("#", apply(rgb, MARGIN=2, FUN=paste, collapse=""), sep="")
  }

# Convert all colors into format "#rrggbb"
  getColorTable <- function(col) {
    rgb <- col2rgb(col);
    col <- rgb2col(rgb);
    sort(unique(col))
  }
############################################################################
############################################################################


#################################### MAIN ##################################
############################################################################

# import groupings from the data file or input arguments
  if ( is.na(my_grouping)[1]==TRUE ){ # if groupings are in the data file, get the one specified in the input args
    groups_raw <- strsplit( x=readLines( con=file_in, n=group_lines ), split="\t" ) 
    my_groups <- groups_raw[[1]][ 2:(length(groups_raw[[1]])) ] # skip first -- should be empty -- field
  }else{
    my_groups <- my_grouping
  }

# import data
  my_data <- read.table(
                        file_in,
                        header=TRUE,
                        stringsAsFactors=FALSE,
                        sep="\t",
                        comment.char="",
                        quote="",
                        check.names=FALSE,
                        row.names=1,
                        skip=group_lines
                        )

# get dimensions of the data
  my_data.n_rows <- nrow(my_data)
  my_data.n_cols <- ncol(my_data)

# make sure that number of group designations matches the numbe of samples, die if they are not correct
  if ( length(my_groups) != my_data.n_cols ){ stop(  paste("Group assignments (", length(my_groups), ") does not match number of samples (",my_data.n_cols, ")", sep="" )  ) }

# get the sums and averages for all columns in the data
  my_data.sum <- as.matrix(rowSums(my_data))
  colnames(my_data.sum) <- "sum_all_samples"
  my_data.mean <- as.matrix(rowMeans(my_data))
  colnames(my_data.mean) <- "mean_all_samples"

# name the groups vector with sample ids from the imported data
  names(my_groups) <- colnames(my_data)

# factor the groups
  my_groups.factor <- factor(my_groups)

# get the levels of the factors (get the list of unique groups)
  my_groups.levels <- levels(factor(my_groups))

# get the number of groups
  num_groups <- nlevels(my_groups.factor)

# sigtest to perform stats
# place selected stat in variable for use below
# my_stat = "Kruskal-Wallis"
# perform stat tests (uses matR)
  my_stats <- sigtest(my_data, my_groups, stat_test)

# Create headers for the data columns
  for (i in 1:dim(my_data)[2]){
    colnames(my_data)[i] <- paste( colnames(my_data)[i], "::", (my_groups)[i], sep="" )
  }
  for (i in 1:dim(my_stats$mean)[2]){
    colnames(my_stats$mean)[i] <- paste( colnames(my_stats$mean)[i], "::group_mean", sep="" )
  }
  for (i in 1:dim(my_stats$sd)[2]){
    colnames(my_stats$sd)[i] <- paste( colnames(my_stats$sd)[i], "::group_sd", sep="" )
  }
  my_stats.statistic <- as.matrix(my_stats$statistic)
  colnames(my_stats.statistic) <- paste(stat_test, "::stat", sep="")
  my_stats.p <- as.matrix(my_stats$p.value)
  colnames(my_stats.p) <- paste(stat_test, "::p", sep="")
  my_stats.fdr <- as.matrix(p.adjust(my_stats$p.value))
  colnames(my_stats.fdr) <- paste(stat_test, "::fdr", sep="")

# generate a summary object - used to generate the plots, and can be used to create a flat file output
  my_stats.summary <- cbind(my_data, my_data.mean, my_stats$mean, my_stats$sd, my_stats.statistic, my_stats.p, my_stats.fdr)

# make sure that order_by value, if other than NULL is supplied, is valid
  if (is.null(order_by)){ # use last column by default, or specified column otherwise
    order_by <- ( ncol(my_stats.summary) )
  } else {
    if (is.integer(order_by)){
      if ( order_by > ncol(my_stats.summary) ){
        stop( paste(
                    "\n\norder_by (", order_by,") must be an integer between 1 and ",
                    ncol(my_stats.summary),
                    " (max number of columns in the output)\n\n",
                    sep="",
                    collaps=""
                    ) )
      }
    }else{
      stop( paste(
                  "\n\norder_by (", order_by,") must be an integer between 1 and ",
                  ncol(my_stats.summary),
                  " (max number of columns in the output)\n\n",
                  sep="",
                  collaps=""
                  ) )
    }
  }

# order the data by the selected column - placing ordered data in a new object
  my_stats.summary.ordered <- my_stats.summary[ order(my_stats.summary[,order_by], decreasing=order_decreasing), ]

# flat file output of the summary file
  write.table(my_stats.summary.ordered, file = file_out, col.names=NA, row.names = rownames(my_stats.summary), sep="\t", quote=FALSE)

# create a subselection of the data above based on selected number of categories
  my_stats.summary.ordered.subset <- as.matrix(my_stats.summary.ordered[1:my_n,])
  profile_indices <- as.numeric(grep("group_mean", colnames(my_stats.summary.ordered.subset)))

# Rotate the subselected data so its suitable for the barplot function
  my_stats.summary.ordered.subset.rot_90 <- rot90(  my_stats.summary.ordered.subset[,profile_indices]  )

# Genrate colors based on the number of groups
  my_data.color <- col.wheel(num_groups)

# create the barplot if that option is chossen- as pdf - legend on left, barplot on right
  if ( identical( is.null(figure_out), NULL ) == FALSE){
    pdf ( file=figure_out, width=8.5, height=4 )
    split.screen(c(1,2))
    screen(1)
    text( x=0.5, y=0.9 ,labels=paste(
                        "file in:  ",file_in, "\n",
                        "file out: ",file_out, "\n",
                        "sorted by output column ", order_by, ", \"",colnames(my_stats.summary.ordered)[order_by], "\"", "\n",
                        "Number of categories: ", my_n,
                        sep=""
                        ) )
    legend( x="center", legend=rownames(my_stats.summary.ordered.subset.rot_90), pch=15, col=my_data.color )
    screen(2)
    barplot( 
          my_stats.summary.ordered.subset.rot_90, 
          beside=TRUE, 
          col=my_data.color,
          las=2
          )
  
    dev.off()
  }
}
