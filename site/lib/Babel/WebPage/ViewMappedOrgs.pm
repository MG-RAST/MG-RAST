package AnnotationClearingHouse::WebPage::ViewMappedOrgs;

use strict;
use warnings;

use FIG;

use base qw( WebPage );

1;

sub init{
  my ($self) = @_;
  
  $self->application->register_component('Table','OrganismList' );
  $self->application->register_action($self, 'update_mapping', 'Submit selection');
}


sub output {
  my ($self) = @_;
  
  my $fig = new FIG;
  my $cgi = $self->application->cgi();
  my $html = [];
  
  # User name and login from the WebApplication
  my $user   = $self->application->session->user;

  
  my $dbf = $fig->db_handle;
  
  # show only duplucates from check file
  my $check  = $cgi->param('duplicates') || 0 ; 
  # Message
  $self->app->add_message('info' , "Check is $check" );
  
  my $source = $cgi->param('source') || "UniProt";
  $source=lc($source);
  # prepare select box
  
  my $box = $cgi->popup_menu(-name=>'source',
			     -values=>['UniProt','NCBI','IMG','CMR','KEGG'],
			     -default=>'UniProt',
			    );
  
  
  # get data
  
  my $tab = $self->make_table($fig , $source , $check);
  my $table = $self->application->component('OrganismList');
  $table->data($tab);
  $table->columns( [ 
		    # { 'name' => 'Example SEED ID' },
		    # { 'name' => 'Example external ID',filter => 1, sortable => 1 },
		    { 'name' => 'SEED Organism', 'filter' => 1 , sortable => 1},
		    { 'name' => 'External Organism' , 'filter'=>1  , sortable=> 1},
		    { 'name' => 'SEED protein sequences', sortable => 1 },
		    { 'name' => 'External protein sequences' , sortable => 1 },
		    { 'name' => 'Common protein sequences' , filter => 1, operators => [ 'more', 'less' , "equal" , "unequal"  ]  , sortable => 1 },
		   ]
		 );
  $table->show_top_browse(1);
  $table->show_bottom_browse(1);
  $table->items_per_page(500);
  $table->show_select_items_per_page(1);

  push(@$html,$cgi->h2("Mapped organism")); 
  push(@$html,"<p>Please select a data source to see the existing organism mapping. The current data source is ".uc($source).":</p>");  
  
  push @$html , $self->start_form('select_source_form');
  push @$html , "<p>Source: ".$box;
  push @$html , "<input type='submit' name='select source' value='Select Source'></p>";
  push @$html , $self->end_form();
  
  push @$html , $self->start_form('mapping_form');
  push @$html ,  "<input type=\"hidden\" name=\"source\" value=\"$source\">";
  push @$html ,  "<input type=\"hidden\" name=\"duplicates\" value=\"$check\">";
  push @$html , "<hr>\n";
  push @$html , "<p><input type='submit' name='action' value='Submit selection'></p>"  if ($user->has_right( $self->application , 'view' , 'organism' ) );
  push @$html , $table->output();
  push @$html , "<p><input type='submit' name='action' value='Submit selection'></p>"  if ($user->has_right( $self->application , 'view' , 'organism' ) );
  push @$html , $self->end_form();
  
  return join("",@$html);
}

sub make_table {
  my($self,$fig , $source, $check) = @_;

  my $user   = $self->application->session->user;

  $source=lc($source);
  my $file    = "overview_org_mapping_seed2".$source;
  my $qa_file = "ach_mapped_orgs_seed2$source".".tsv";

  my @table ;

  my $seen = {};
  my @duplicates;

  # read id 2 organism name mapping
  my $org = {};
  open(ORG , "</vol/clearinghouse/data/ach_org2id.tsv");
  
  # skip first line;
  my $tmp = <ORG>;
  
  while( my $line = <ORG> ){
    chomp $line;
    my ($id , $name) = split "\t" , $line;
    $org->{ $name } = $id ;
  }
  close ORG;


  # read handled mappings
  my $exclude = {};
  open(QA , "/vol/clearinghouse/data/". $qa_file);
  while( my $line = <QA> ){
    chomp $line;
    print STDERR $line;
    my ($seed_org , $source_org , $status) = split "\t" , $line;
    $exclude->{ $seed_org } = { org => $source_org,
				status => $status,};
    
  }
  close(QA);


  # load overview

  open(FILE , "/vol/clearinghouse/data/". $file );
  
  # skip first line
  #  my $tmp = <FILE>;
  
  my $groups = {};
  
  while( my $line = <FILE> ){
    chomp $line;
    my ($seed_org , $source_org , $s_id , $e_id , $seed_pegs , $source_pegs , $hits ) = split "\t" , $line;
    
    # skip non seed orgs
    next unless( $seed_org ); 
    next if ( $exclude->{ $org->{ $seed_org} } and  $exclude->{ $org->{ $seed_org} }->{ status } eq "ignore"  );  
    
    $seen->{ $source_org }++;
    if( $seen->{ $source_org } > 1){
      push @duplicates , $source_org;
    }

    my @line;
    push @line ,  ($seed_org , $source_org , $seed_pegs , $source_pegs , $hits );
    
    if ($user->has_right( $self->application , 'view' , 'organism' ) ){
      push @line , $self->application->cgi->popup_menu( -name   => "mapping.". $org->{ $seed_org}."\t". $org->{ $source_org} ,
							-values => [ 'Accept' , 'Ignore']);
      push @line , "<a href=\"?page=comment_orgs&source=$source&seed=".$org->{ $seed_org}."&external=".$org->{ $source_org }."\" target=\"comment\">comment</a>";
    }


    push @{ $groups->{ $seed_org  } } , \@line ;
  }
  close(FILE);
  
  foreach my $var ( sort { $a cmp $b } keys %$groups){
    my $group = $groups->{ $var }; 
    push @table , @$group
  }

  if (scalar @duplicates){
    $self->app->add_message('info' , "This organisms are mapped multiple times to a seed organism<br>" . join "<br> " , @duplicates );
  }
    
  return \@table;
}



sub update_mapping{
  my ($self) = @_;
  
  my $cgi = $self->app->cgi;
  my $source = $cgi->param('source');
  $source = lc($source);
  #my $dbh  = $self->data('ach');

  my $user = $self->application->session->user;
  my @params = $cgi->param();  
  
  open(MAPPED , ">>/vol/clearinghouse/data/ach_mapped_orgs_seed2$source.tsv");

  foreach my $param (@params){
    if ( my ($prefix , $pair) = $param =~ /(mapping\.)(.+)/ ){
      
	my $status =  $cgi->param($param);
	my ($seed , $ext) = split "\t" , $pair;
	if  ($cgi->param($param) eq "Ignore"){
	  print MAPPED "$seed\t$ext\t".lc($status)."\n";
	  
	  # Message
	  $self->app->add_message('info' , "You set $seed   <b>versus</b> $ext to <b>" . $cgi->param($param) ."</b>" );
	}
      }
    
  }
  
  close(MAPPED);
}
