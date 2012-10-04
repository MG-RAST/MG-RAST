package MGRAST::Statistics;

use strict;
use warnings;
use Data::Dumper;

use Conf;
use DBI;

1;

# need to check if db handles passed in and create if necessary
# use WebApplicationDBHandle;
# my ($dbmaster, $error) = WebApplicationDBHandle->new();
# fail if error found

sub new {
  my($class, $mgrast_dbh, $user_dbh) = @_;

  my $self = { 
               mgrast_dbh => $mgrast_dbh,
	       user_dbh   => $user_dbh,
	     };

  bless ($self, $class);
  return $self;
}

sub mgrast_dbh {
    my ($self) = @_;
    return $self->{mgrast_dbh};
}

sub user_dbh {
    my ($self) = @_;
    return $self->{user_dbh};
}

sub registered_users {
    my($self, $time) = @_;
    
    my $sql   = "select user, current_page from UserSession where timestamp > '$time' and user is not null";
    my $users = $self->user_dbh->selectall_arrayref($sql);
    return $users;
}

sub number_of_users {
    my($self, $time) = @_;

    my $sql   = "select count(*) from UserSession where timestamp > '$time'";
    my $users = $self->user_dbh->selectall_arrayref($sql);
    return $users;
}

sub job_count {
    my($self) = @_;
    
    my $sql   = "select substring(created_on,1,7) as Date, count(job_id) as Jobs from Job where job_id is not NULL group by Date";
    my $count = $self->mgrast_dbh->selectall_arrayref($sql);
    return $count;
}

sub get_funding_users {
    my($self) = @_;

    my $funding_users = $self->user_dbh->selectall_arrayref("select value, count(*) from Preferences where name = 'funding_source' group by value");
    return $funding_users;
}

sub get_funding_user_jobs {
    my ($self, $mapping) = @_;
    
    my $lf = {};
    my $job_data  = $self->mgrast_dbh->selectall_arrayref("select owner, _id from Job where owner is not NULL");
    my $user_data = $self->user_dbh->selectall_arrayref("select _id, email from User");
    my $fund_data = $self->user_dbh->selectall_arrayref("select user, value from Preferences where name = 'funding_source'");
    my $stat_data = $self->mgrast_dbh->selectall_arrayref("select job, value from JobStatistics where tag = 'bp_count_raw' and value is not NULL and value > 0");
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
	while ( my ($ext, $code) = each %$mapping ) {
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


