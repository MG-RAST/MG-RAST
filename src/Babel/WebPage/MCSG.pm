package Babel::WebPage::MCSG;



use strict;
use warnings;
use LWP::Simple;
use Data::Dumper;
use Babel::lib::Babel;
use base qw( WebPage );

1;


sub init {
  my $self = shift;
  $self->title("MCSG - Target");

  # register components
  $self->application->register_component('Table', 'Targets');
  $self->application->register_component('Table', 'Overview');

  # get data handler, connect to database and initialise babel
  my $dbh = $self->app->data_handle('Babel');
  print STDERR "DBhandle = $dbh\n";
  $self->data('babel' , Babel::lib::Babel->new( $dbh ) );


 

}

# commented out frontend to search by keywords

sub output {
  my ($self) = @_;
  
  my $path    = "/home/wilke/data/liz/MCSG-Target";
  my $cgi     = $self->app->cgi;
  my $content = "";
  
  if ( $cgi->param('file') ){
    $content .= $self->load_file( $path , $cgi->param('file') );
  }
  else{
    $content .= $self->load_file_list( $path );
  }
  return $content;
}





sub load_file_list{
  my ($self , $path) = @_;
  my $content = "";
  if (-d $path){
    # $content = $path;
    my $summary = {};
    
    my $tax2org = $self->load_tax2org_mapping($path);

    my $header = [ { name => "Organism"    , filter => 1 , sortable => 1 },
		   { name => "Taxonomy ID" , filter => 1 , sortable => 1 },
		   { name => "Hydrophobicity"   , filter => 1 , sortable => 1 },
		   { name => "Timestamp"   , filter => 1 , sortable => 1 },
		   ];
    
    my $data = [];
    opendir(DIR , $path) or die "Can't open dir $path\n";
    
    while ( my $file = readdir DIR ){
      next unless ($file =~ /\.txt$/);
      my ($tax , $organelle , $date) = $file =~/targets_([^_]+)_([^_]+)_(\d+-\d+-\d+)\.txt/;

      unless ($tax2org->{$tax} ){
	my $org = $self->get_entries_for_tax_id($tax);
	$self->add_tax2org_mapping($path , $tax2org , $tax , $org);
      }
      #$content .= "<tr><th><a href='?page=MCSG&file=$file'>" . $tax2org->{$tax}. "</a></th><td>" . ($tax || $file) ." </td><td>$organelle</td><td>$date</td></tr>\n";

      my @row =  ( "<a href='?page=MCSG&file=$file'>" . $tax2org->{$tax}. "</a>" , $tax , $organelle , $date);
      push @$data , \@row;
    }
    
    my @sorted = sort { $b->[3] cmp $a->[3] } @$data ; 

    
    # build table
    my $table_component = $self->application->component('Overview');
    $table_component->data( \@sorted );
    $table_component->columns( $header );
    $table_component->show_top_browse(1);
    $table_component->show_bottom_browse(1);
    $table_component->items_per_page(50);
    $table_component->show_select_items_per_page(1);
    $content .=  $table_component->output();

  }
  else{
    $content = "No valid path to summary files";
  }

  return $content;
}

sub load_file{
  my ($self , $path , $file) = @_;
  my $content = "";
  
  if (-f "$path/$file"){
    
    $content .= "<table>\n";
    open(FILE , "$path/$file") or die "Can't open $file\n";

    # get header 
    my $header = <FILE>;
    chomp $header;
    my $hline = [];
    foreach my $e (split "\t" , $header){
      push @$hline , { 'name'=>$e , filter=>1 };
    }
 

    # read file and get data
    my $data = [];
    while (my $line = <FILE>){
      chomp $line;
      my (@entries) = split "\t" , $line;

      my $babel  = $self->data('babel');
      my $md5set = $babel->id2md5($entries[0]);
      my $md5    = "" ;
      
      next unless (ref $md5set->[0] and scalar @{ $md5set->[0] });
      $md5       =  $md5set->[0]->[0];
      my $set    = $babel->md52id4source( $md5 , 'SEED' );
      
      # $self->app->add_message('info' , Dumper $set);

      if (ref $set and ref $set->[0]) {
	my $id  = $entries[0];
	my $url = "http://seed-viewer.theseed.org/linkin.cgi?id=" . $set->[0]->[0];
	$entries[0] = "<a href=$url>$id</a>";
      }

      
      push @$data , \@entries ; 
    }
    close(FILE);


    # build table
    my $table_component = $self->application->component('Targets');
    $table_component->data( $data );
    $table_component->columns( $hline );
    $table_component->show_top_browse(1);
    $table_component->show_bottom_browse(1);
    $table_component->items_per_page(50);
    $table_component->show_select_items_per_page(1);
    $content .=  $table_component->output();

    
  }
  else{
    $content .= "<p>No file $file</p>";
  }
  
  return $content;
}



sub get_entries_for_tax_id{
  my ($self , $tax_id) = @_;
  
  return "unknown" unless ($tax_id =~/^\d+$/);
  my $url = "http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=Info&id=";
  my $search_result = get($url.$tax_id);
  
  my $url_seq_overview = "http://www.ncbi.nlm.nih.gov/";
  

  my $content     = "";

  # print $search_result;
  
  my @lines = split ( "\n" , $search_result);
  
  my $nr_seq = 0;
  my $nr_proj = 0; 
  my $url_seq = "";
  my $url_proj = "";
  my $genome_name = "";
  
  my $next = "";
  foreach my $line ( @lines ){
    
    if ( $next eq "Sequences"){
      ($url_seq)   = $line =~ m/href=\"([^\"]*)\"/;
      ($nr_seq) = $line =~ m/>(\d*)<\/font/;
      
      print STDERR "Genome Sequences: $nr_seq\n";
      $url_seq =~s/&amp;/&/g;
      # print "URL:\t$url_seq\n";
      
      $next = "";
    }
    elsif ( $next eq "Projects"){
      ($url_proj) = $line =~ m/href=\"([^\"]*)\"/;
      ($nr_proj) = $line =~ m/>(\d*)<\/font/;
      
      
      print STDERR "Genome Projects: $nr_proj \n";

     
      $next = "";
    }
    
    if ( $line =~ /<title>Taxonomy browser/ ){
      # print STDERR $line,"\n";
    }
    if ( $line =~ m/<title>Taxonomy browser/){
        # print STDERR $line,"\n";
      
    }
    if ( $line =~ /<title>Taxonomy browser\s*\(([^()]+)\)\<\/title\>/ ) {
      $genome_name = $1;
      print STDERR "Genome Name = $1\n";
    }
    
    if ($line =~ m/(Genome[\w;&]+Sequence)/){
      $next = "Sequences";
    } 
    elsif ($line =~ m/(Genome[\w;&]+Projects)/){
      $next = "Projects";
    }
    
  }
  
  
#   my $page =  get($url_seq_overview.$url_seq);  
#   my (@ids) = $page =~m/www.ncbi.nlm.nih.gov\/sites\/entrez\?Db=genome\&amp\;Cmd=ShowDetailView\&amp\;TermToSearch=\d+\">(\w+)<\/a>/gc;
#   #<a href="http://www.ncbi.nlm.nih.gov/sites/entrez?Db=genome&amp;Cmd=ShowDetailView&amp;TermToSearch=19221">AC_000091</a>
#   # print @ids , "\n";
  
#   # get sequence file
#   my $query = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=".join ("," , @ids) ."&rettype=gb" ;
#   my $file = get($query);
#   my ($project) = $file =~/DBLINK\s+(Project:\d+)/;
#   $content .=  "Project $project\n";


 

  return "$genome_name";
}

sub load_tax2org_mapping{
  my ($self , $path) = @_;
  
  my $mapping = {} ;
  open(FILE , "$path/tax2org_mapping") or return $mapping ;
  while(my $line = <FILE>){
    chomp $line;
    my ($tax , $org) = split "\t" , $line;
    $mapping->{$tax} = $org ;
  }
  
  return $mapping;
}

sub add_tax2org_mapping{
  my ($self , $path , $mapping , $tax , $org) = @_;
  
  $mapping->{$tax} = $org ;
  open(FILE , ">>$path/tax2org_mapping") or return $mapping ;
  print FILE "$tax\t$org\n";
  close FILE;
  
  return $mapping;
}
