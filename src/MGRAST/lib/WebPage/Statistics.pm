package MGRAST::WebPage::Statistics;

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use WebComponent::WebGD;
use GD;
use Data::Dumper;
use MGRAST::Analysis;
use MGRAST::Metadata;

1;

=pod
    
    =head1 NAME

Statistics - an instance of WebPage which lets the user see statistcs for MGRAST

=head1 DESCRIPTION

Display statistics

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {

  my ($self) = @_;
  
  $self->title("MG-RAST Statistics");
  $self->{icon} = "<img src='./Html/mgrast_globe.png' style='width: 20px; height: 20px; padding-right: 5px; position: relative; top: -3px;'>";

  # register components
  $self->application->register_component('Ajax', 'ajax');
  $self->application->register_component('DataFinder', "d");
  $self->application->register_component('Hover', 'help');
  $self->application->register_component('Table', 'FundingSources');
  $self->application->register_component('Table', 'FundingSourcesClean');
  $self->application->register_component('Table', 'JobsMonth');
  

  my $email_mapping = {
		       "cdc.gov"     => "CDC" ,
		       "dhec.sc.gov" =>	"DHEC",
		       "anl.gov"     =>	"DOE" ,
		       "lnl.gov"     => "DOE" ,
		       "lanl.gov"    => "DOE" ,
		       "lbl.gov"     => "DOE" ,
		       "nrel.gov"    => "DOE" ,
		       "ornl.gov"    => "DOE" ,
		       "pnl.gov"     => "DOE" ,
		       "sandia.gov"  => "DOE" ,
		       "doe.gov"     =>	"DOE" ,
		       "epa.gov"     => "EPA" ,
		       "fda.hhs.gov" =>	"FDA" ,
		       "nih.gov"     =>	"NIH" ,
		       "noaa.gov"    =>	"NOAA",
		       "usda.gov"    =>	"USDA",
		       "usgs.gov"    =>	"USGS",
		       "va.gov"      =>	"VA"
		      };
    $self->data('mapping' , $email_mapping);

  return 1;

}

sub output {
    my ($self) = @_;
    
    my $application = $self->application;
    my $dbmaster    = $application->dbmaster;
    my $user        = $application->session->user;
    my $cgi         = $application->cgi;
    my $offline     = "<h2>The MG-RAST is currently offline. We apologize for the inconvenience. Please try again later.</h2>";
    
    # check for MGRAST
    my $mgrast_dbh = $self->application->data_handle('MGRAST')->db_handle;
    my $user_dbh   = $user->_master->db_handle;
    unless ($mgrast_dbh) {
      return $offline;
    }

    ### funding sources counts
    my $table_a = $self->application->component('FundingSources');
    my $data_a  = $user_dbh->selectall_arrayref("select value, count(*) from Preferences where name = 'funding_source' group by value");
    unless ($data_a) { return $offline; }

    @$data_a = sort { $a->[0] cmp $b->[0] } @$data_a;
    my ($pie_a, $div_a) = &get_piechart("pie_a", "Funding Sources", ['Organization', 'Count'], $data_a, 20);
    
    $table_a->width(850);
    if ( scalar(@$data_a) > 25 ) {
	$table_a->show_top_browse(1);
	$table_a->show_bottom_browse(1);
	$table_a->items_per_page(25);
	$table_a->show_select_items_per_page(1); 
    }
    $table_a->columns([ { name => 'Funding Source', sortable => 1, filter => 1 },
			{ name => 'Count', sortable => 1 }
		      ]);
    $table_a->data($data_a);
    $table_a->show_export_button({title => 'export', strip_html => 1});

    ### funding sources user and job
    my $table_b = $self->application->component('FundingSourcesClean');
    my $data_b  = $self->get_funding_user_jobs($mgrast_dbh, $user_dbh); # fund, user, job, bp

    my @fund_usr = map { [$_->[0], $_->[1]] } @$data_b;
    my @fund_job = map { [$_->[0], $_->[2]] } @$data_b;
    my @fund_bps = map { [$_->[0], sprintf("%.3f", ($_->[3] * 1.0)/1000000000)] } @$data_b;

    my ($pie_usr, $div_usr) = &get_piechart("pie_usr", "Users per funding source", ['Organization', 'Users'], \@fund_usr, 0);
    my ($pie_job, $div_job) = &get_piechart("pie_job", "Jobs per funding source", ['Organization', 'Jobs'], \@fund_job, 20);
    my ($pie_bps, $div_bps) = &get_piechart("pie_bps", "Gbps per funding source", ['Organization', 'Gbps'], \@fund_bps, 20);
    my $div_b = "<table><tr><td>$div_usr</td><td>$div_job</td><td>$div_bps</td></tr></table>";
    
    $table_b->width(850);
    if ( scalar(@$data_b) > 25 ) {
      $table_b->show_top_browse(1);
      $table_b->show_bottom_browse(1);
      $table_b->items_per_page(25);
      $table_b->show_select_items_per_page(1); 
    }
    $table_b->columns([ { name => 'Funding Source', sortable => 1, filter => 1},
			{ name => 'Users', sortable  => 1 , filter => 1 },
			{ name => 'Jobs', sortable  => 1 },
			{ name => 'Basepairs', sortable => 1 }
		      ]);
    $table_b->data($data_b);
    $table_b->show_export_button({title => 'export', strip_html => 1});

    ### job counts
    my $data_c  = $mgrast_dbh->selectall_arrayref("select substring(created_on,1,7) as Date, count(job_id) as Jobs from Job where job_id is not NULL group by Date");
    my $table_c = $self->application->component('JobsMonth');
    my ($pie_c, $div_c) = &get_piechart("pie_c", "Jobs per Month", ['Month', 'Jobs'], $data_c, 20);
  
    $table_c->width(850);
    if ( scalar(@$data_c) > 25 ) {
      $table_c->show_top_browse(1);
      $table_c->show_bottom_browse(1);
      $table_c->items_per_page(25);
      $table_c->show_select_items_per_page(1); 
    }
    $table_c->columns([ { name => 'Period', sortable => 1 },
			{ name => 'Jobs', sortable => 1 }
		      ]);    
    $table_c->data($data_c);
    $table_c->show_export_button({title => 'export', strip_html => 1});

    my $html = $pie_a . $pie_usr . $pie_job . $pie_bps . $pie_c;
    $html   .= "<h3>Funding Sources</h3>" . $table_a->output . $div_a;
    $html   .= "<h3>Funding Stats</h3>" . $table_b->output . $div_b;
    $html   .= "<h3>Monthly Job Usage</h3>" . $table_c->output . $div_c;
    
    return $html . "<br>";
}

sub get_funding_user_jobs {
    my ($self, $job_dbh, $user_dbh) = @_;
    
    my $lf = {};
    my $job_data  = $job_dbh->selectall_arrayref("select owner, _id from Job where owner is not NULL");
    my $user_data = $user_dbh->selectall_arrayref("select _id, email from User");
    my $fund_data = $user_dbh->selectall_arrayref("select user, value from Preferences where name = 'funding_source'");
    my $stat_data = $job_dbh->selectall_arrayref("select job, value from JobStatistics where tag = 'bp_count_raw' and value is not NULL and value > 0");
    unless ($user_data && $fund_data && $job_data) { return $lf; }
    
    my %user_jobs  = ();
    my %user_email = map { $_->[0], $_->[1] } @$user_data;
    my %user_fund  = map { $_->[0], uc($_->[1]) } @$fund_data;
    my %job_stats  = ($stat_data && (@$stat_data > 0)) ? map { $_->[0], $_->[1] } @$stat_data : ();

    map { push @{ $user_jobs{$_->[0]} }, $_->[1] } @$job_data;

    foreach my $user (keys %user_email) {
      if (($user == 122) || ($user == 7232)) { next; }  # skip Wilke

      my $fund = exists($user_fund{$user}) ? $user_fund{$user} : '';
      my $jobs = exists($user_jobs{$user}) ? $user_jobs{$user} : [];
      my $bps  = 0;
      map { $bps += $job_stats{$_} } grep { exists $job_stats{$_} } @$jobs;
      
      my $has_fund = 0;
      if ($fund) {
	$lf->{$fund}{users}++;
	$lf->{$fund}{jobs} += scalar(@$jobs);
	$lf->{$fund}{bp_count_raw} += $bps;
	$has_fund = 1;
      }
      else {
	while ( my ($ext, $code) = each %{$self->data('mapping')} ) {
	  if ( $user_email{$user} =~ /$ext$/ ) {
	    $lf->{$code}{users}++;
	    $lf->{$code}{jobs} += scalar(@$jobs);
	    $lf->{$code}{bp_count_raw} += $bps;
	    $has_fund = 1;
	  }
	}
      }
    }
    
    my @res = map { [ $_, $lf->{$_}{users}, $lf->{$_}{jobs}, $lf->{$_}{bp_count_raw} ] } sort keys %$lf;
    return \@res;
}

sub get_piechart {
  my ($id, $title, $cols, $data, $left) = @_;

  my $num  = scalar @$data;
  my $rows = join("\n", map { qq(data.addRow(["$_->[0]", $_->[1]]);) } sort { $b->[1] <=> $a->[1] } @$data);
  my $pie  = qq~
    <script type="text/javascript">
      google.load("visualization", "1", {packages:["corechart"]});
      google.setOnLoadCallback(drawChart);
      function drawChart() {
        var color = GooglePalette($num);
        var data  = new google.visualization.DataTable();
        data.addColumn('string', '$cols->[0]');
        data.addColumn('number', '$cols->[1]');
        $rows
        var chart = new google.visualization.PieChart(document.getElementById('$id'));
        chart.draw(data, {width: 300, height: 300, colors: color, chartArea: {left:$left, width:"90%"}, title: '$title'});
      }
    </script>
~;

  return ($pie, "<div id='$id'></div>");
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/rgbcolor.js", "https://www.google.com/jsapi"];
}
