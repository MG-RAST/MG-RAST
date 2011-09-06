package ToolBox::WebPage::IDMapping;



use strict;
use warnings;

use AnnoClearinghouse;
use FIG;

use Mail::Mailer;
use DBKernel;
use HTML;
use URI::Escape;
use Data::Dumper;
use base qw( WebPage );

1;




sub init {
  my $self = shift;
  $self->title("ACH - ID Mapping");
  
  
  #init fig first
  my $fig = new FIG;
  my $ach = AnnoClearinghouse->new( "/vol/clearinghouse/v12" , "/vol/clearinghouse/contrib" , 1);

  my $achDB = DBKernel->new('mysql', 'fig_anno_v5', 'ach', undef, undef, 'anno-3.nmpdr.org');	
  
  $self->data('fig' , $fig);	  
  $self->data('ach' , $ach);
  $self->data( 'db_handle', $achDB );
  $self->data( 'file' ,  $self->app->cgi->param('process_id') || '' );

  $self->data('file' , $self->save_file) if  ($self->app->cgi->param('upload_file') and not  $self->app->cgi->param('process_id') );


  # get list of seed organisms
  my $orgs = {};
  foreach my $id ($fig->genomes){
    $orgs->{ $id } = $fig->genus_species( $id );
  }
  $self->data('seed_orgs' , $orgs);

  # compute stuff

  if ( $self->data('file') and  $self->app->cgi->param('compute_table') ){
    my @ids = $self->app->cgi->param('selected_orgs');
    $self->data('filter_orgs' , \@ids); 
    
    $self->data('table' , $self->compute_table());
    $self->send_email;
  }
  else{

    # get data from file 
    print STDERR "Loading data from file " .$self->data( 'file') ."\n"; 
    $self->load_results if $self->app->cgi->param('process_id')  ;
 
  

   my @params = $self->app->cgi->param();
   print STDERR join (" " , @params) . "\n";
   foreach my $param (@params){
     print STDERR "$param ". $self->app->cgi->param($param) ."\n";
   }
  }

  
  # register components
  $self->application->register_component('TabView', 'Overview');
  $self->application->register_component('Table', 'MappingTable');
  $self->application->register_component('DisplayListSelectSimple', 'OrganismSelect');

}


sub output {
  my ($self) = @_;
  
  my $html= [];
  my $content = "<h1>ID Mapping</h1>";


  # set params for tabview
  my $tab = $self->application->component('Overview');
  $tab->width(800);
  $tab->height(180);

  # set tabs

  $tab->add_tab('Upload file or process ID' , $self->upload_id_file);
  $tab->add_tab('Set parameters', $self->set_parameters); 
  $tab->add_tab('Table', $self->display_table) if ( $self->data('table') and ref $self->data('table') );
 
  # set default tab
  if ( $self->data('file') and not $self->data('table') ){
    $tab->default('1');
  }
  elsif( $self->data('table') ){
    $tab->default('2');
  }

#   my @params = $self->app->cgi->param();
#   $content .= "<p>".join (" " , @params) . "</p>";
  #   foreach my $param (@params){
#     $content .= "$param ". $self->app->cgi->param($param) ."<br>";
#   }

  $content .= join ", " , $self->app->cgi->param('selected_orgs'); 
  
  $content .= "<p>This is a draft version to map external IDs to fig IDs. You have to submit a tab separated file with IDs where the ID has to be in the first column.</p>";

  if ($self->data('file') and $self->data('computed') ){
    #my $file  = $self->save_file;
    $content .= $self->display_mapping_for_file( $self->data('file') );
    # $content .= $self->display_file;
  }
  else{
    $content .= $tab->output;
    #$content .= $self->upload_id_file;
  }
  
    
  

  
  return $content;
}


sub display_mapping_for_file{
  my ($self , $file) = @_;
  my $content;


  # get data from file
  my @data;
  my $max_col = 0;
  
  print STDERR "Reading $file\n";

  open(FILE , $file) or die "Can't open file $file!\n";

  while (my $line = <FILE>){
    my @row;
    chomp $line;
    my @fields  = split "\t" , $line;
    $max_col = scalar @fields if (scalar @fields > $max_col);
    my ($org , $seq) = $self->mapID( $fields[0] );

    my $ids = { org => $org,
		seq => $seq,
	      };

    print STDERR "Get subsystem data\n";
    my $ids_subs= $self->get_subsystem_data( $ids );
    
  
    my $rows = $self->create_mapping_row($ids_subs);

    $fields[0] = "<a href=\"http://clearinghouse.nmpdr.org/aclh.cgi?page=SearchResults&query=".$fields[0]."\">".$fields[0]."</a>";

    foreach my $row (@$rows){
      my @line;
      push @line, @fields , @$row;
      push @data , \@line;
    }
  }

  close(FILE);

  #display data

  $content .= $self->show_mapping_table(\@data , $max_col);

  return $content;
}

sub display_file{
  my ($self) = @_;
  my $content = "";

  my $file = $self->data('file');

  # dateinamen erstellen und die datei auf dem server speichern
  # my $fname = '/tmp/file_'.$$.'_'.$ENV{REMOTE_ADDR}.'_'.time;
  # open DAT,'>'.$fname or die 'Error processing file: ',$!;
  
  # Dateien in den Binaer-Modus schalten
  #binmode $file;
  binmode DAT;
  
  my $data;
  # while(read $file,$data,1024) {
  while(read $file,$data,1024) {
  
    $data =~ s/[\r\n]+/\n/g;
    #print DAT $data; 
    $content .= $data;
  }
  # close DAT;
  
  
  return $content;
}


sub save_file{
  my ($self) = @_;
  my $content = "";

  my $file = $self->app->cgi->param('upload_file');

  # dateinamen erstellen und die datei auf dem server speichern
  my $fname = '/tmp/file_'.$$.'_'.$ENV{REMOTE_ADDR}.'_'.time;
  open DAT,'>'.$fname or die 'Error processing file: ',$!;
  
  # Dateien in den Binaer-Modus schalten
  binmode $file;
  binmode DAT;
  
  my $data;
  # while(read $file,$data,1024) {
  while(read $file,$data,1024) {
  
    $data =~ s/[\r\n]+/\n/g;
    $data =~ s/_at//g; # for veronika , to be removed
    $data =~ s/'//g;
    print DAT $data; 
    #$content .= $data;
  }
  close DAT;
  
  
  return $fname;
}


sub upload_id_file {
  my ( $self ) = @_;
  my $content = "<h3>Upload file of IDs</h3>\n";
 
  $content .= $self->start_form('get_file');
  $content .="
  <p>Please select a file to upload:<br>
    <input name=\"upload_file\" type=\"file\" size=\"100\"  accept=\"text/*\"> <br><br>
    or enter a process ID:  
  <input name=\"process_id\" type=\"text\" size=\"30\">
 <input type=\"submit\"><input type=\"reset\"> 
  </p>
</form>
";

  return $content;
}

sub show_mapping_table{
  my ($self , $data , $nr_col) = @_;
  
  # get table component
  my $table = $self->application->component('MappingTable');
  
  # set table parameter
  $table->width(800);
  if (scalar(@$data) > 50) {
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1);
  }
  $table->show_export_button({ strip_html => 1,
			       hide_invisible_columns => 1,
			     });

  ####
  # define columns
  ###

  my @cols;

  my @supercol;

  for (my $i=0; $i<$nr_col; $i++){
    push @cols ,  { name => '', sortable => 1 , filter => 1 };
  
  }

  # original columns
  push @supercol , [ 'Original columns' , $nr_col];

  # for organism
  push @supercol , [ 'Organism and Sequence based mapping' ,3] ;
  
  # for sequence
  push @supercol ,  [ 'Sequence based mapping', 3 ];

  $table->supercolumns( \@supercol );

  # for organism 
  push @cols ,  { name => 'ID', sortable => 1 , filter => 1 }; 
  push @cols ,  { name => 'Assignment', sortable => 1 , filter => 1 }; 
  push @cols ,  { name => 'Subsystem', sortable => 1 , filter => 1 };

  #for sequence
  push @cols ,  { name => 'ID', sortable => 1 , filter => 1 }; 
  push @cols ,  { name => 'Assignment', sortable => 1 , filter => 1 }; 
  push @cols ,  { name => 'Subsystem', sortable => 1 , filter => 1 };
  $table->columns( \@cols );
  
  # fill table with data
  $table->data($data);

  return $table->output();
}



sub mapID{

  my ($self , $ext_id , $without_aliases , $with_type_info) = @_;

  my $fig  = $self->data('fig');
  my $aclh = $self->data('ach');

 

  my @id_list = $fig->get_corresponding_ids($ext_id, $with_type_info);
  my @ids_seq;
  
   foreach my $line ( $fig->mapped_prot_ids( $ext_id ) ){    
     push @ids_seq , $line->[0]." [". $fig->org_of( $line->[0])."]" ;
   }
  
  unless (scalar (@ids_seq) ){
    # print STDERR "ACH:\n";
    foreach my $line (  $aclh->lookup_id( $ext_id) ){
      foreach my $entry (@$line){
	#print scalar @$entry , "\n";
	#print join "\t" , @$entry , "\n" if (scalar @$entry);
	next unless $entry->[0];
	if ($without_aliases) {
	  # print STDERR "Only FIG";
	  push @ids_seq , $entry->[0] if ($entry->[0] =~/fig\|/);
	}
	else{

	  push @ids_seq , $entry->[0]."[".$entry->[1]."]";
	}
      }
    } 
  }
  
  # only fig IDs
  
  my @org;
  my @seq;
  
  if ($without_aliases) {
    map { push @org , $1 if ($_=~/(fig\|[^;\s]+)/ );  }  @id_list; 
    map { push @seq , $1 if ($_=~/(fig\|[^;\s]+)/ );  }  @ids_seq;
  }
  else{
    @org = @id_list; 
    @seq = @ids_seq;
  }
  
  return (\@org , \@seq) ;
}

sub get_subsystem_data{
  my ( $self, $peg ) = @_;
  my $data = {};
  my $fig = $self->data('fig');

  unless ($peg) {
    print STDERR "No peg $peg in get_subsystem data\n";
    exit;
  }

  my @subs = $fig->subsystems_for_peg($peg);

  if (scalar @subs){
    foreach my $tuple ( @subs ){
      my($sub,$role) = @$tuple;
      my $subO = new Subsystem($sub,$fig);
	    
      if (! $subO) { 
	#warn "BAD SUBSYSTEM: $sub $peg\n"; 
	push @{$data->{''}->{pegs}} , $peg ;
	push @{$data->{''}->{class}} , '' , '' ;
      }
      elsif( $fig->is_experimental_subsystem( $sub ) or $fig->is_private_subsystem( $sub ) ){
	push @{$data->{''}->{pegs}} , $peg ;
	push @{$data->{''}->{class}} , '' , '' ;
      }
      else{
	my $class = $subO->get_classification;

	my $level_1 = $class->[0] || '';
	my $level_2 = $class->[1] || '';
	#print STDERR "Classification $level_1 :::: $level_2\n";
	push @{$data->{$sub}->{class}} , $level_1 , $level_2 ;
	push @{$data->{$sub}->{pegs}} , $peg ;
      }
    }
  }
  else{
    push @{$data->{''}->{pegs}} , $peg ;
    push @{$data->{''}->{class}} , '' , '' ;
  }

  return $data;
  
}
    
sub create_mapping_row{
  my ($self , $ids ) = @_;

  my @org_rows;
  my @seq_rows;
  my @data;


  my @org_ids = keys %{ $ids->{org} };
  my @seq_ids = keys %{ $ids->{seq} };

 

  if (scalar @org_ids){
  }
  else{
    my @row;
    push @row , "" , "" , "";
    push @org_rows , \@row;
  }

  if (scalar @seq_ids){
    foreach my $peg ( @seq_ids){
      my $subs =   $ids->{ seq }->{ $peg }->{ subsystem } ;
      my $func =   $ids->{ seq }->{ $peg }->{ func } || "unknown";
      if ($subs and scalar @$subs){
	foreach my $sub (@$subs){
	  my @row;
	  push @row , $peg , $func, $sub->{subsystem};
	  push @seq_rows , \@row;
	}
      }
      else{
	my @row;
	push @row , $peg , $func, "";
	push @seq_rows , \@row;
      }
	
    }
  }
  else{
    my @row;
    push @row , "wrong" , "" , "";
    push @seq_rows , \@row;
  }

  foreach my $org (@org_rows){
    foreach my $seq (@seq_rows){
      my @row;
      push @row , @$org , @$seq;
      push @data , \@row;
    }
  }
  #return \@rows;
  return \@data;
}



sub set_parameters{
  my ($self) = @_;
 
  # set params
  
  my $form_name = 'get_params';
  my $my_email  = 'your@email.here'; 
  my $data = {};
  $data->{ genome_id } =  'Ecoli'; 
  $data->{ bartels_id } =  'Bartels';
  
  # get select box
  my $box = $self->application->component('OrganismSelect');
  $box->data( $self->data('seed_orgs') );
  $box->form( $form_name , 0 ); 
  $box->list_name( "selected_orgs" ); 
  $box->list_headers( "SEED organisms:" , "Selected organisms:");
  $box->submit_button('compute_table' , "Compute table");


  my $content = "<p>You have to select somem parameters to compute and display your process ".$self->data('file').".</p>";

  $content .= $self->start_form( $form_name );
  $content .= "<p>";
  $content .= "<table><tr><td>\n";
  $content .= "<input type=\"hidden\" name=\"process_id\" value=\"".$self->data('file')."\">";
  $content .= "
    <input type=\"radio\" name=\"compute\" value=\"only_ids\" checked> Get ID mapping<br>
    <input type=\"radio\" name=\"compute\" value=\"function\"> Get IDs and function<br>
    <input type=\"radio\" name=\"compute\" value=\"subsystem\"> Get IDs with function and subsystem<br>
  ";
  $content .= "</td><td>\n"; 
  $content .= "Restrict mapping to organism:<br>\n".$box->output();

 

  $content .= "</td><tr></table>\n";
  $content .= "</p>";
  $content .= "<p>Computation may take a while, if you leave an email address you will be informed when your data is ready: <br><input type=\"text\" name=\"email\" value=\"$my_email\"></p>\n";
  $content .= $self->end_form();
  return $content;
}





# compute table and mapping

# wrapper to compute data for different params
# returns table data for display table

sub compute_table{

  my ($self) = @_;

  my $info =  $self->app->cgi->param('compute') || '';
  
  my $data = { table    => '', # array ref
	       supercol => '', # array ref
	       col      => '', # array ref
	     };

  my $input = $self->data('file');
  
  if ( $info eq "only_ids"){

    my ($table, $col , $scol) = $self->compute_id_mapping;

    $data->{table}    = $table;
    $data->{col}      = $col;
    $data->{supercol} = $scol;
  }
  elsif ($info){

    my ($table, $col , $scol) = $self->compute_id_mapping( $info );

    $data->{table}    = $table;
    $data->{col}      = $col;
    $data->{supercol} = $scol;
  }
  else{
    print STDERR "Wrong selection in compute_table\n";
  }

 
  my $itext = "Data stored.";
  $itext = "Data not stored" unless ( $self->store_results($data) );
    
  $self->app->add_message('info' , $itext);


  return $data;
}



sub compute_id_mapping{
  my ($self , $info ) = @_;

  my $fig = $self->data('fig');
  my $file = $self->data('file');

  # get data from file
  my @data;
  my $max_col = 0;

  my $filter = {};
 
  # set filter
  foreach my $var (@{ $self->data('filter_orgs')}){
    $filter->{ $var } = 1;
   
  }


  open(FILE , $file) or die "Can't open file $file!\n";

  while (my $line = <FILE>){

    # get IDs from file
    chomp $line;
    my @fields  = split "\t" , $line;
    $max_col = scalar @fields if (scalar @fields > $max_col);

    # get mapping for ID
    my ($org , $seq) = $self->mapID( $fields[0] , $info);


    # filter ids
    my @filtered_org;
    foreach my $peg (@$org){

	my ($sid) = $peg =~/fig\|(\d+\.\d+)/;

	next if ( scalar @{$self->data('filter_orgs')} and not $filter->{ $sid});
	push @filtered_org , $peg ;
      }   
    $org = \@filtered_org;


    my @filtered_seq;
    foreach my $peg (@$seq){

	my ($sid) = $peg =~/fig\|(\d+\.\d+)/;
	
	print STDERR "No 'filter_orgs'" unless $self->data('filter_orgs');
	print STDERR "Empty 'filter_orgs'" unless scalar @{$self->data('filter_orgs')} ;

	next if ( scalar @{$self->data('filter_orgs')} and not  $filter->{$sid}  );
	push @filtered_seq , $peg ;
      }   
    $seq = \@filtered_seq;
    
    
    # SET LINK TO CLEARINGHOUSE
    $fields[0] = "<a href=\"http://clearinghouse.nmpdr.org/aclh.cgi?page=SearchResults&query=".$fields[0]."\">".$fields[0]."</a>";
    
    if( $info and $info eq "function" ){
     
      my $id_org = {};
      $id_org->{ '' } = [] unless scalar @$org; 
      
      my $id_seq = {};
      $id_seq->{ '' } = [] unless scalar @$seq;

      foreach my $peg (@$org){

	#my ($sid) = $peg =~/fig\|(\d+\.\d+)/;
	#next if ( scalar @{$self->data('selected_orgs')} and not $filter->{ $sid});

	push @{ $id_org->{  $fig->function_of($peg) } } , $peg ;
      }   

      foreach my $peg (@$seq){

	#my ($sid) = $peg =~/fig\|(\d+\.\d+)/;
	#next if ( scalar @{$self->data('selected_orgs')} and not $filter->{ $sid});

	push @{ $id_seq->{  $fig->function_of($peg) } } , $peg ;
      }
   

      foreach my $o (keys %$id_org){

	foreach my $s (keys %$id_seq){

	  my @row = ( (join " " , @{$id_org->{ $o }} ) , $o ,  (join " " , @{$id_seq->{ $s }} ) , $s );
	  my @line;
	  push @line, @fields , @row;
	  push @data , \@line;
	}

      }


    }
    elsif( $info and $info eq "subsystem" ){
      
      
      my $id_org = {};
      $id_org->{ '' }->{ '' } = [] unless scalar @$org; 
      
      my $id_seq = {};
      $id_seq->{ '' }->{ '' }->{ 'pegs'  => [],
				 'class' => '',
			       } = [] unless scalar @$seq;
      
      #
      # get function and subsystem data for pegs (seq - org)
      #
      
      foreach my $peg (@$org){

	my $func  = $fig->function_of($peg);
	my @subs = $fig->subsystems_for_peg($peg);

	if (scalar @subs){
	  foreach my $tuple ( @subs ){
	    my($sub,$role) = @$tuple;
	    my $subO = new Subsystem($sub,$fig);
	    
	    if (! $subO) { 
	      warn "BAD SUBSYSTEM: $sub $peg\n"; 
	      push @{ $id_org->{ $func }->{''} } , $peg ;
	    }
	    else{
	      push @{ $id_org->{ $func }->{ $sub } } , $peg ;
	    }
	  }
	}
	else{
	  push @{ $id_org->{ $func }->{''} } , $peg ;
	}

      }   

      foreach my $peg (@$seq){
	
	#
	# get function and subsystem data for pegs (seq)
	#
	
	my $func  = $fig->function_of($peg) || '';
	my @subs = $fig->subsystems_for_peg($peg);

	$id_seq->{ $func } = $self->get_subsystem_data( $peg );
	
      }
   
  
      foreach my $of (keys %$id_org){ 
	foreach my $os (keys %{$id_org->{ $of }}){

	  foreach my $sf (keys %$id_seq){
	  
	    foreach my $ss (keys %{$id_seq->{ $sf } }){

	      $id_seq->{ $sf }->{$ss}->{pegs} = [ "no peg" ] unless  $id_seq->{ $sf }->{$ss}->{pegs};
	   
	      #print STDERR "Here $sf : $ss : " .$id_seq->{ $sf }->{$ss}->{pegs}."\n";
	      #print STDERR "$sf $ss " .$id_seq->{ $sf }->{$ss}->{class}."\n";
	      
	      my @row = ( (join " " , @{$id_org->{ $of }->{ $os }} ) , $of , $os ,  (join " " , @{ $id_seq->{ $sf }->{$ss}->{pegs} } ) , $sf , $ss  ,  $id_seq->{ $sf }->{$ss}->{class}->[0] ,  $id_seq->{ $sf }->{$ss}->{class}->[1]  );

	      my @line;
	      push @line, @fields , @row;
	      push @data , \@line;
	    }
	

	  }
	}
      }
  
    }
    else{
      
      # set rows for table
      my @row;
      push @row , join " " , @$org;
      push @row , join " " , @$seq;
      
      
      my @line;
      push @line, @fields , @row;
      push @data , \@line;
    }
  }

  close(FILE);
  
  # define columns
  my (@scol , @col);
  
  for (my $i=0; $i<$max_col; $i++){
    push @col ,  { name => '', sortable => 1 , filter => 1 };
  }
  if ($info and $info eq "function"){
    # original columns
    push @scol , [ 'Original columns' , $max_col];
    
    # for organism
    push @scol , [ 'Organism and Sequence based mapping' ,2] ;
    
    # for sequence
    push @scol ,  [ 'Sequence based mapping', 2 ];
    
    
    push @col ,  { name => 'ID', sortable => 1 , filter => 1 };
    push @col ,  { name => 'Assignment', sortable => 1 , filter => 1 };
    push @col ,  { name => 'ID', sortable => 1 , filter => 1 };
    push @col ,  { name => 'Assignment', sortable => 1 , filter => 1 };
  }
  elsif( $info and $info eq "subsystem"){
    # original columns
    push @scol , [ 'Original columns' , $max_col];
    
    # for organism
    push @scol , [ 'Organism and Sequence based mapping' ,3] ;
    
    # for sequence
    push @scol ,  [ 'Sequence based mapping', 5 ];
    
    
    push @col ,  { name => 'ID', sortable => 1 , filter => 1 };
    push @col ,  { name => 'Assignment', sortable => 1 , filter => 1 }; 
    push @col ,  { name => 'Subsystem', sortable => 1 , filter => 1 };
    push @col ,  { name => 'ID', sortable => 1 , filter => 1 };
    push @col ,  { name => 'Assignment', sortable => 1 , filter => 1 };
    push @col ,  { name => 'Subsystem', sortable => 1 , filter => 1 }; 
    push @col ,  { name => 'Subsystem Classification 1', sortable => 1 , filter => 1 };
    push @col ,  { name => 'Subsystem Classification 2', sortable => 1 , filter => 1 };
  }
  else{
       # original columns
    push @scol , [ 'Original columns' , $max_col];
    
    # for organism
    push @scol , [ 'Organism and Sequence based mapping' ,1] ;
    
    # for sequence
    push @scol ,  [ 'Sequence based mapping', 1 ];

    push @col ,  { name => 'Organism and sequence based ID mapping', sortable => 1 , filter => 1 };
    push @col ,  { name => 'Sequence based ID mapping', sortable => 1 , filter => 1 };
  }
  
  
  return (\@data , \@col , \@scol);
}







# display methods

sub display_table{
  my ($self) = @_;
  

  print STDERR "Display TABLE\n";
 
  my $table_info = $self->data('table');

  my $data  = $table_info->{table};
  my $cols  = $table_info->{col};
  my $scols = $table_info->{supercol};

  print STDERR "Table rows: " . scalar @$data ."\n";
  # get table component
  my $table = $self->application->component('MappingTable');
  
  # set table parameter
  $table->width(800);
  if (scalar(@$data) > 50) {
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(50);
    $table->show_select_items_per_page(1);
  }
  $table->show_export_button({ strip_html => 1,
			       hide_invisible_columns => 1,
			     });

 
  # set columns

  $table->supercolumns( $scols ) if (ref $scols and scalar @$scols);
  $table->columns( $cols );
  
  # fill table with data
  
  $table->data($data);

  return $table->output();
}


sub store_results{
  
  my ($self , $table_info) = @_;
  my $file = "";
  my $data  = $table_info->{table};
  my $cols  = $table_info->{col};
  my $scols = $table_info->{supercol};
  
  $file = $self->data('file').".res" if  $self->data('file');
  
  if ($file){
    
    
    if (ref $scols and scalar @$scols){
      open (FILE , ">$file.scol" ) or die "Can't open $file.scol for writing!\n";
      print FILE Dumper( $scols );
      close FILE;
    }   
    
    if (ref $cols and scalar @$cols){  
      open (FILE , ">$file.col" ) or die "Can't open $file.col for writing!\n";
      print FILE Dumper( $cols );
      close FILE;
    }
    
    
    if (ref $data and scalar @$data){
      open (FILE , ">$file.data" ) or die "Can't open $file.data for writing!\n";
      print FILE Dumper( $data );
      close FILE;
    }
    
  }
  else{
    print STDERR "Can't store results, no file!\n";
    return 0;
  }
  
  return 1;
}

sub load_results{
  
  my ($self) = @_;
  my $file = "";
  my $data;
  my $col;
  my $scol;
  my $table_info = {};
  
  $file = $self->data('file').".res" if  $self->data('file');
  
  if (-f $file.".scol" and
      -f $file.".col" and 
      -f $file.".data")
    {
    
    open (FILE , "<$file.scol" ) or warn "Can't open $file.scol for reading!\n";
    while (<FILE>){ $scol .= $_; }
    
    close FILE;
    
    open (FILE , "<$file.col" ) or warn "Can't open $file.col for reading!\n";
    while (<FILE>){ chomp $_; $col .= $_; }
   
    close FILE;    

    open (FILE , "<$file.data" ) or warn "Can't open $file.data for reading!\n"; 
    while (<FILE>){ $data .= $_; }
    close FILE;
    
    # print STDERR Dumper( $data );

    $table_info->{table}    = eval "my $data"  unless (ref $data);
    $table_info->{col}      = eval "my $col"   unless (ref $col);
    $table_info->{supercol} = eval "my $scol"  unless (ref $scol);

    $self->data('table' , $table_info);

 
  }
  else{
    print STDERR "Can't load results, no file!\n";
    return 0;
  }
  
  return 1;
}


sub send_email{
  my ($self) = @_;

  
  if  ($self->app->cgi->param('email') and 
       $self->app->cgi->param('email') ne 'your@email.here' ){
    
    my $pid = $self->app->cgi->param('process_id') ;
    my $to =  $self->app->cgi->param('email');

    my $body = "Your data is ready. 
Please click here: 
http://bioseed.mcs.anl.gov/~wilke/FIG/toolBox.cgi?page=IDMapping&process_id=".$pid." 
 to see your data or go to the the ToolBox and enter your PID $pid\n";
    

    my $mailer = Mail::Mailer->new();
    $mailer->open({ From    => 'Andreas.Wilke@mcs.anl.gov',
		    To      => $to,
		    Subject => "Table is ready",
		  })
      or die "Can't open Mail::Mailer: $!\n";
    print $mailer $body;
    $mailer->close();
    
   
    
  }
  
}
