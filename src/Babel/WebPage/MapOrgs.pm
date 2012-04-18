package AnnotationClearingHouse::WebPage::MapOrgs;

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

#    my $fig = $self->application->data_handle('FIG');
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
		       { 'name' => 'External Organism' , 'filter'=>1  },
		       { 'name' => 'total number of organism pairs for this seed organism', sortable => 1 },
		       { 'name' => 'Same Organisms' },
		       { 'name' => '' },
		     ]
                   );
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(500);
    $table->show_select_items_per_page(1);

 
    if($check){
      push(@$html,$cgi->h2("Review problems in organism mapping")); 
      push(@$html,"<p>Please recheck following organisms for $source. It seems that the $source organism name has been assigned multiple times to differen SEED organism names:</p>");  
    }
    else{
      push(@$html,$cgi->h2("Mapping of the unknown")); 
      push(@$html,"<p>Please map following organisms for $source:</p>");  
    }

    push @$html , $self->start_form('select_source_form');
    push @$html , $box;
    push @$html , "<p><input type='submit' name='select source' value='Select Source'></p>";
    push @$html ,  "<input type=\"hidden\" name=\"duplicates\" value=\"$check\">";
    push @$html , $self->end_form();
    
    push @$html , $self->start_form('mapping_form');
    push @$html ,  "<input type=\"hidden\" name=\"source\" value=\"$source\">";
    push @$html ,  "<input type=\"hidden\" name=\"duplicates\" value=\"$check\">";
    push @$html , "<p><input type='submit' name='action' value='Submit selection'></p>";
    push @$html , $table->output();
    push @$html , "<p><input type='submit' name='action' value='Submit selection'></p>";
    push @$html , $self->end_form();

    return join("",@$html);
}

sub make_table {
    my($self,$fig , $source, $check) = @_;

    $source=lc($source);
    my $files = { uniprot => 'seed2uniprot_org' ,
		  ncbi    => 'seed2ncbi_org' ,
		  cmr     => 'seed2cmr_org',
		  kegg    => 'seed2kegg_org',
		  img     => 'seed2img_org',
		};

    my $to_check = {};
    if ($check){
      open(CHECK , "/vol/clearinghouse/data/check_mapped_seed2$source"."_org");
      $self->app->add_message('info' , "Reading /vol/clearinghouse/data/check_mapped_seed2$source"."_org" );
      while( my $line = <CHECK> ){
	chomp $line;
	 my ($ext , $seed) = split "\t" , $line;
	 $to_check->{$seed} = 1;
      }
    }
    



    my $mapped = {};
    open(MAPPED , "/vol/clearinghouse/data/ach_mapped_orgs_seed2$source.tsv");
    
    while( my $line = <MAPPED> ){
      chomp $line;
      my ($seed , $ext) = split "\t" , $line;
      $mapped->{$seed} = $ext;
    }
    
    close(MAPPED);

    my $org = {};
    open(ORG , "</vol/clearinghouse/data/ach_org2id.tsv");

    # skip first line;
    my $tmp = <ORG>;

    while( my $line = <ORG> ){
      chomp $line;
      my ($id , $name) = split "\t" , $line;
      $org->{ $id } = $name ;
    }
    close ORG;

    my @table ;


    open(FILE , "/vol/clearinghouse/data/". $files->{$source} );

    # skip first line
   #  my $tmp = <FILE>;

    my $groups = {};

      while( my $line = <FILE> ){
      chomp $line;
      my ($fig_org , $ext_org , $count ) = split "\t" , $line;
      
      # skip non seed orgs
      next unless( $fig_org );
      
      # skip if organism is already mapped
      next if ($mapped->{ $fig_org } );

      next if ($check and !($to_check->{ $fig_org }) );


      my @line;
      my $name = "mapping.$fig_org\t$ext_org";
      my $box = "Same: <input type='radio' name='$name' value='same'> <br>Ignore  <input type='radio' name='$name' value='ignore'>";
      my $submit = "<p><input type='submit' name='action' value='Submit selection'>";

      push @line ,  ( $org->{$fig_org} || $fig_org , $org->{$ext_org} , $count , $box , $submit);

      push @{ $groups->{ $org->{$fig_org} } } , \@line ;

    }
    close(FILE);
    
    foreach my $var ( sort { $a cmp $b } keys %$groups){
      my $group = $groups->{ $var };
      print STDERR $group->[0]->[1];
      my @g = sort { $b->[2] <=> $a->[2] } @$group;
      push @g , [ '' , '<b>NEXT</b>' ,'', '' , ''] ;
      push @table , @g
    }

  
   
    
    return \@table;
}



sub update_mapping{
  my ($self) = @_;
  
  my $cgi = $self->app->cgi;
  my $source = $cgi->param('source');
  lc($source);
  #my $dbh  = $self->data('ach');

  my $user = $self->application->session->user;
  my @params = $cgi->param();
  
  
  open(MAPPED , ">>/vol/clearinghouse/data/ach_mapped_orgs_seed2$source.tsv");

  foreach my $param (@params){
    if ( my ($prefix , $pair) = $param =~ /(mapping\.)(.+)/ ){
      
	my $status =  $cgi->param($param);
	my ($seed , $ext) = split "\t" , $pair;
	print MAPPED "$seed\t$ext\t$status\n";
	
	# Message
	$self->app->add_message('info' , "You set $seed   <b>versus</b> $ext to <b>" . $cgi->param($param) ."</b>" );
		
      }
    
  }
  
  close(MAPPED);
}
