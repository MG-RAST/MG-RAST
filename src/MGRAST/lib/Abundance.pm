package MGRAST::Abundance;

use strict;
use warnings;
no warnings('once');

use DBI;
use Data::Dumper;
use List::Util qw(max min sum);

our $ontology_md5s = {}; # src => ont => [md5s]
our $function_md5s = {}; # func => [md5s]
our $organism_md5s = {}; # org => [md5s]
our $md5_abundance = {}; # md5 => abund
our $dbh = undef;

sub get_analysis_dbh {
    eval {
      my $host     = $Conf::mgrast_dbhost;
      my $database = $Conf::mgrast_db;
      my $user     = $Conf::mgrast_dbuser;
      my $password = $Conf::mgrast_dbpass;
      
      $dbh = DBI->connect("DBI:Pg:dbname=$database;host=$host", $user, $password, 
			  { RaiseError => 1, AutoCommit => 0, PrintError => 0 }) ||
			    die $DBI::errstr;
    };
    if ($@) {
      warn "Unable to connect to metagenomics database: $@\n";
    }
}

sub get_ontology_abundances {
    my ($job, $ver) = @_;
    
    my $data = {}; # src => id => level1
    my $ont_md5  = {}; # src => lvl1 => { md5s }
    my $ont_nums = {}; # src => [ lvl1, abundance ]
    
    my $sql  = "SELECT distinct s.name, o._id, o.level1 FROM ontologies o, sources s WHERE o.source=s._id";
    my $rows = $dbh->selectall_arrayref($sql);
    unless ($rows && (@$rows > 0)) {
        return {};
    }
    map { $data->{$_->[0]}{$_->[1]} = $_->[2] } grep { $_->[2] && ($_->[2] =~ /\S/) } @$rows;
  
    my $onts = get_ontology_md5s($dbh, $job, $ver);
    foreach my $s (keys %$onts) {
        foreach my $o (keys %{$onts->{$s}}) {
            if (exists $data->{$s}{$o}) {
                map { $ont_md5->{$s}{$data->{$s}{$o}}->{$_} = 1 } @{ $onts->{$s}{$o} };
            }
        }
    }
    
    my $md5s = get_md5_abundance($dbh, $job, $ver);
    foreach my $s (sort keys %$ont_md5) {
        foreach my $d (sort keys %{$ont_md5->{$s}}) {
            my $num = 0;
            map { $num += $md5s->{$_} } grep { exists $md5s->{$_} } keys %{ $ont_md5->{$s}{$d} };
            if ($num > 0) {
  	            push @{$ont_nums->{$s}}, [ $d, $num ];
            }
        }
    }
    
    return $ont_nums;
}

sub get_function_abundances {
    my ($job, $ver) = @_;

    my $data = {}; # id => function
    my $func_md5 = {}; # function => { md5s }
    my $func_num = []; # [ function, abundance ]

    my $rows = $dbh->selectall_arrayref("SELECT _id, name FROM functions");
    unless ($rows && (@$rows > 0)) {
        return [];
    }
    %$data = map { $_->[0], $_->[1] } grep { $_->[1] && ($_->[1] =~ /\S/) } @$rows;
  
    my $funcs = get_function_md5s($dbh, $job, $ver);
    foreach my $f (keys %$funcs) {
        if (exists $data->{$f}) {
            map { $func_md5->{$data->{$f}}->{$_} = 1 } @{ $funcs->{$f} };
        }
    }

    my $md5s  = get_md5_abundance($dbh, $job, $ver);
    my $other = 0;
    foreach my $f (sort keys %$func_md5) {
        my $num = 0;
        map { $num += $md5s->{$_} } grep { exists $md5s->{$_} } keys %{ $func_md5->{$f} };
        if ($num > 0) {
            push @$func_num, [ $f, $num ];
        }
    }
    
    return $func_num;
}

sub get_taxa_abundances {
    my ($job, $taxa, $clump, $ver) = @_;

    my $data = {}; # id => taxa
    my $tax_md5 = {}; # taxa => { md5s }
    my $tax_num = []; # [ taxa, abundance ]
    
    my $rows = $dbh->selectall_arrayref("SELECT distinct _id, tax_$taxa FROM organisms_ncbi");
    unless ($rows && (@$rows > 0)) {
        return [];
    }
    %$data = map { $_->[0], $_->[1] } grep { $_->[1] && ($_->[1] =~ /\S/) } @$rows;
  
    my $orgs = get_organism_md5s($dbh, $job, $ver);
    foreach my $o (keys %$orgs) {
        if (exists $data->{$o}) {
            map { $tax_md5->{$data->{$o}}->{$_} = 1 } @{ $orgs->{$o} };
        }
    }
    
    my $md5s  = get_md5_abundance($dbh, $job, $ver);
    my $other = 0;
    foreach my $d (sort keys %$tax_md5) {
        my $num = 0;
        map { $num += $md5s->{$_} } grep { exists $md5s->{$_} } keys %{ $tax_md5->{$d} };
        if ($clump && ($d =~ /other|unknown|unclassified/)) {
            $other += $num;
        } else {
            if ($num > 0) {
	            push @$tax_num, [ $d, $num ];
            }
        }
    }
    if ($clump && ($other > 0)) {
        push @$tax_num, [ "Other", $other ];
    }
    
    return $tax_num;
}

sub get_ontology_md5s {
    my ($job, $ver) = @_;
    unless (scalar(keys %$ontology_md5s) > 0) {
        my $sql = "SELECT distinct s.name, j.id, j.md5s FROM job_ontologies j, sources s WHERE j.version=$ver AND j.job=$job AND j.source=s._id";
        my $rows = $dbh->selectall_arrayref($sql);
        if ($rows && (@$rows > 0)) {
            map { $ontology_md5s->{$_->[0]}{$_->[1]} = $_->[2] } @$rows;
        }
    }
    return $ontology_md5s;
}

sub get_function_md5s {
    my ($job, $ver) = @_;
    unless (scalar(keys %$function_md5s) > 0) {
        my $rows = $dbh->selectall_arrayref("SELECT distinct id, md5s FROM job_functions WHERE version=$ver AND job=$job");
        if ($rows && (@$rows > 0)) {
            %$function_md5s = map { $_->[0], $_->[1] } @$rows;
        }
    }
    return $function_md5s;
}

sub get_organism_md5s {
    my ($job, $ver) = @_;
    unless (scalar(keys %$organism_md5s) > 0) {
        my $rows = $dbh->selectall_arrayref("SELECT distinct id, md5s FROM job_organisms WHERE version=$ver AND job=$job");
        if ($rows && (@$rows > 0)) {
            %$organism_md5s = map { $_->[0], $_->[1] } @$rows;
        }
    }
    return $organism_md5s;
}

sub get_md5_abundance {
    my ($job, $ver) = @_;
    unless (scalar(keys %$md5_abundance) > 0) {
        my $rows = $dbh->selectall_arrayref("SELECT distinct md5, abundance FROM job_md5s WHERE version=$ver AND job=$job");
        if ($rows && (@$rows > 0)) {
            %$md5_abundance = map { $_->[0], $_->[1] } @$rows;
        }
    }
    return $md5_abundance;
}

sub get_alpha_diversity {
    my ($job, $ver) = @_;
    
    my $alpha = 0;
    my $h1    = 0;
    my @nums  = map { $_->[1] } @{ get_taxa_abundances($dbh, $job, 'species', undef, $ver) };
    my $sum   = sum @nums;
    
    unless ($sum) {
        return $alpha;
    }
    foreach my $num (@nums) {
        my $p = $num / $sum;
        if ($p > 0) { $h1 += ($p * log(1/$p)) / log(2); }
    }
    $alpha = 2 ** $h1;
    
    return $alpha;
}

sub get_rarefaction_xy {
    my ($job, $nseq, $ver) = @_;
    
    my $rare = [];
    my $size = ($nseq > 1000) ? int($nseq / 1000) : 1;
    my @nums = sort {$a <=> $b} map {$_->[1]} @{ get_taxa_abundances($dbh, $job, 'species', undef, $ver) };
    my $k    = scalar @nums;

    for (my $n = 0; $n < $nseq; $n += $size) {
        my $coeff = nCr2ln($nseq, $n);
        my $curr  = 0;
        map { $curr += exp( nCr2ln($nseq - $_, $n) - $coeff ) } @nums;
        push @$rare, [ $n, $k - $curr ];
    }
    
    return $rare;
}

# log of N choose R 
sub nCr2ln {
    my ($n, $r) = @_;

    my $c = 1;
    if ($r > $n) {
        return $c;
    }
    if (($r < 50) && ($n < 50)) {
        map { $c = ($c * ($n - $_)) / ($_ + 1) } (0..($r-1));
        return log($c);
    }
    if ($r <= $n) {
        $c = gammaln($n + 1) - gammaln($r + 1) - gammaln($n - $r); 
    } else {
        $c = -1000;
    }
    return $c;
}

# This is Stirling's formula for gammaln, used for calculating nCr
sub gammaln {
    my ($x) = @_;
    unless ($x > 0) { return 0; }
    my $s = log($x);
    return log(2 * 3.14159265458) / 2 + $x * $s + $s / 2 - $x;
}

1;