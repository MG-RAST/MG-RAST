make_public_list<- function(num_mg=10, verbose=FALSE){
  
  # this script will create a list of the first 10 public metagenomes
  require(RJSONIO, RCurl) # required, non base packages
  
  my_call <- paste("http://api.metagenomics.anl.gov/1/metagenome?status=public&limit=", num_mg, sep="")

  if(verbose==TRUE){print(my_call)}
  
  my_json <- fromJSON(getURL(my_call))
  
  my_mgid_list <- vector(mode = "character", length = num_mg)
  
  for (i in 1:num_mg){
    my_mgid_list[i] <- as.character(my_json$data[[1]]['id'])
  }
  
  return(my_mgid_list)
}