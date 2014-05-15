package WebComponent::SearchMetagenome;

# SearchMetagenome - component for a search box

use strict;
use warnings;

use base qw( WebComponent );

use DBI;
use Conf;

1;


=pod

=head1 NAME

SearchMetagenome - component for a search box

=head1 DESCRIPTION

WebComponent for a search box

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->{target_link} = "MetagenomeOverview";
  $self->{data} = [];
  $self->{show_result} = 1;
  $self->{show_exact_option} = 1;
  $self->{button_title} = 'find';
  $self->{job_db} = 'jobcache_MG_prod';
  $self->{meta_db} = 'MGRASTMetadata';
  $self->{data_db} = 'mgrast_job_data_prod';

  $self->application->register_component('Table', 'search_result_table'.$self->id);

  return $self;
}

=item * B<output> ()

Returns the html output of the Searchmetagenome component.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $page = $application->page;
  my $cgi = $application->cgi;
  my $user = $application->session->user;

  my $exact = "";
  if ($self->show_exact_option) {
    my $checked_exact = '';
    if ($cgi->param('mg_exact'.$self->id)) {
      $checked_exact = ' checked=checked';
    }
    my $checked_matchall = '';
    if ($cgi->param('mg_matchall'.$self->id)) {
      $checked_matchall = ' checked=checked';
    }
    $exact = "<br><input type='checkbox' name='mg_exact".$self->id."'$checked_exact> exact match <input type='checkbox' name='mg_matchall".$self->id."'$checked_matchall> match all";
  }
  my $previous_value = "";
  if (defined($cgi->param('mg_search'.$self->id))) {
    $previous_value = " value='" . $cgi->param('mg_search'.$self->id) . "'";
  }
  my $search = $page->start_form."Search for <input type='text' name='mg_search".$self->id."'$previous_value> in  " ;
  $search .= $cgi->popup_menu(-name=>'menu_name',
			      -values=>[qw/function.data organism.data metadata all.data.metadata/],
			      -labels=>{
					'function.data'     =>'functions',
					'organism.data'     =>'organisms',
					'metadata'          =>'meta data',
					'all.data.metadata' => 'all',
				       },
			      -default=>'all.data.metadata');
  $search .= "<input type=submit value='".$self->button_title."'> $exact".$page->end_form;
  $search .= "<p>\n";

  if (defined($cgi->param('mg_search'.$self->id))) {
    my $searchword = lc $cgi->param('mg_search'.$self->id);
    my @terms = split(/\s/, $searchword);
    

    # connect to databases
    my $dbh_job = $self->dbh();       # metadata db
    my $dbh_data = $self->dbh_data ;  # data summary / sims db

    # store results
    my $all_results = [];

    my $fields = "id, genome_id, genome_name, project_name, size, public";
    
    if ($cgi->param('mg_matchall'.$self->id)) {
      @terms = ($searchword);
    }
    foreach my $term (@terms) {
      my $how = " like '%$term%'";
      if ($cgi->param('mg_exact'.$self->id)) {
	$how = "='$term'";
      }
      
      # search job ids
      my $statement = "SELECT $fields from Job where id$how and viewable=1";
      my $result = $dbh_job->selectall_arrayref($statement);
      push(@$all_results, map { [ 'job', @$_, "", "" ] } @$result);
      
      # search genome ids
      $statement = "SELECT $fields from Job where genome_id$how and viewable=1";
      $result = $dbh_job->selectall_arrayref($statement);
      push(@$all_results, map { [ 'id', @$_, "", "" ] } @$result);
      
      # search genome names
      $statement = "SELECT $fields from Job where lower(genome_name)$how and viewable=1";
      $result = $dbh_job->selectall_arrayref($statement);
      push(@$all_results, map { [ 'metagenome', @$_, "", "" ] } @$result);
      
      # search project names
      $statement = "SELECT $fields from Job where lower(project_name)$how and viewable=1";
      $result = $dbh_job->selectall_arrayref($statement);
      push(@$all_results, map { [ 'project', @$_, "", "" ] } @$result);
      
      # search metadata values
      $statement = "SELECT tag, $fields, tag, value from Job JOIN " . $self->meta_db . ".JobMD on Job._id=" . $self->meta_db . ".JobMD.job where lower(" . $self->meta_db . ".JobMD.value)$how";
      $result = $dbh_job->selectall_arrayref($statement);
      push(@$all_results, map { [ @$_ ] } @$result);
      
      # search metadata tags
      $statement = "SELECT tag, $fields, tag, value from Job JOIN " . $self->meta_db . ".JobMD on Job._id=" . $self->meta_db . ".JobMD.job where lower(" . $self->meta_db . ".JobMD.tag)$how";
      $result = $dbh_job->selectall_arrayref($statement);
      push(@$all_results, map { [ @$_ ] } @$result);


      # search organisms / functions
      $statement = "SELECT name , abundance , type , jobs  from data_summary  where name ~* '$term' ";
      $result = $dbh_data->selectall_arrayref($statement);
      #my $fields = "id, genome_id, genome_name, project_name, size, public";
      print STDERR "Results :: " . scalar @$result;
      unless (scalar @$result){
	print STDERR $statement ;
      }
      else{

	push(@$all_results, map { [ $_->[2] , (join "," , @{ $_->[3] } ) , '' ,'' ,'' ,'' ,'1' , $_->[0] , $_->[1] ] } @$result);
      }
    }

    $dbh_job->disconnect;
    
  
    

    # filter results for visibility
    my $filtered_results = [];
    my $attribute_hit = 0;
    if ($user) {
      my $ids = $user->has_right_to(undef, 'view', 'metagenome');
      if (scalar(@$ids)) {
	if ($ids->[0] eq '*') {
	  foreach my $r (@$all_results) {
	    unless ($r->[6]) {
	      if ($r->[7]) {
		$attribute_hit = 1;
	      }
	      push(@$filtered_results, $r);
	    }
	  }
	} else {
	  my %id_hash = map { $_ => 1 } @$ids;
	  foreach my $r (@$all_results) {
	    if ($id_hash{$r->[2]} && ! $r->[6]) {
	      if ($r->[7]) {
		$attribute_hit = 1;
	      }
	      push(@$filtered_results, $r);
	    }
	  }
	}
      }
    }
    foreach my $r (@$all_results) {
      if ($r->[6]) {
	if ($r->[7]) {
	  $attribute_hit = 1;
	}
	push(@$filtered_results, $r);
      }
    }

    # sort the results
    @$filtered_results = sort { $a->[0] cmp $b->[0] || $a->[4] cmp $b->[4] || $a->[2] cmp $b->[2] } @$filtered_results;

    $self->data($filtered_results);

    # format results
    my $formatted_results = [];
    foreach my $r (@$filtered_results) {
      if ($r->[6]) {
	$r->[6] = 'yes';
      } else {
	$r->[6] = 'no';
      }
      $r->[3] = '<a href="?page=MetagenomeOverview&metagenome='.$r->[2].'">'.$r->[3].'</a>';
      push(@$formatted_results, $r);
    }

    if ($self->show_result) {
      if (scalar(@$formatted_results)) {
	my $result_table = $application->component('search_result_table'.$self->id);
	$result_table->columns( [ { name => "search column" , filter => 1, operator => 'combobox'}, { name => "job", filter => 1, visible => 0 }, { name => "id", filter => 1, visible => 0 }, { name => "metagenome", filter => 1 }, { name => "project", filter => 1, operator => 'combobox' }, { name => "size", sortable => 1, visible => 0 }, { name => "public", filter => 1, operator => 'combobox' }, { name => "attribute", filter => 1, visible => $attribute_hit, sortable => 1 }, { name => "value", filter => 1, visible => $attribute_hit, sortable => 1 } ] );
	$result_table->data($formatted_results);
	$result_table->items_per_page(20);
	$result_table->show_top_browse(1);
	$result_table->show_bottom_browse(1);
	$result_table->show_select_items_per_page(1);
	$result_table->show_column_select(1);
	$result_table->show_export_button(1);
	$search .= "<h3>Search Result</h3>" . $result_table->output();
      } else {
	$search .= "<p>Your search for '$searchword' did not yield any results.</p>";
      }
    }
  }

  return $search;
}

sub target_link {
  my ($self, $link) = @_;

  if (defined($link)) {
    $self->{target_link} = $link;
  }

  return $self->{target_link};
}

sub dbh {
  my ($self) = @_;

  my $db = $self->job_db;
  my $host = $Conf::mgrast_metadata_host || "";
  my $user = $Conf::mgrast_metadata_user || "root";
  my $password = $Conf::mgrast_metadata_password || "";

  my $connect = "DBI:mysql:database=$db";
  $connect .= ";host=$host" if ($host);
  $user = (defined $user) ? $user : '';
  $password = (defined $password) ? $password : '';

  # initialize database handle.
  my $dbh = DBI->connect($connect, $user, $password, 
			 { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
			   Confess("Database connect error.");

  return $dbh;
}

sub dbh_data {
  my ($self) = @_;

  my $db = $self->data_db || $Conf::mgrast_db ;
  my $host = $Conf::mgrast_dbhost || "";
  my $user = $Conf::mgrast_dbuser || "root";
  my $password = $Conf::mgrast_dbpass || "";


  my $connect = "DBI:Pg:dbname=$db";
  $connect .= ";host=$host" if ($host);
  $user = (defined $user) ? $user : '';
  $password = (defined $password) ? $password : '';

  # initialize database handle.
  my $dbh = DBI->connect($connect, $user, $password, 
			 { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
			   Confess("Database connect error.");

  return $dbh;
}

sub meta_db {
  my ($self, $db) = @_;

  if (defined($db)) {
    $self->{meta_db} = $db;
  }

  return $self->{meta_db};
}

sub job_db {
  my ($self, $db) = @_;

  if (defined($db)) {
    $self->{job_db} = $db;
  }

  return $self->{job_db};
}

sub data_db {
  my ($self, $db) = @_;

  if (defined($db)) {
    $self->{data_db} = $db;
  }

  return $self->{data_db};
}

sub data {
  my ($self, $data) = @_;

  if (defined($data)) {
    $self->{data} = $data;
  }

  return $self->{data};
}

sub show_result {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_result} = $show;
  }

  return $self->{show_result};
}

sub show_exact_option {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_exact_option} = $show;
  }

  return $self->{show_exact_option};
}

sub show_column_filter {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_column_filter} = $show;
  }

  return $self->{show_column_filter};
}

sub button_title {
  my ($self, $title) = @_;
  
  if (defined($title)) {
    $self->{button_title} = $title;
  }

  return $self->{button_title};
}
