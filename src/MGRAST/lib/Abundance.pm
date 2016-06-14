package MGRAST::Abundance;

use strict;
use warnings;
no warnings('once');

use DBI;
use Data::Dumper;
use List::Util qw(max min sum);
use List::MoreUtils qw(natatime);

1;

sub new {
    my ($class, $chdl, $version) = @_;
  
    # connect to database
    my $dbh = undef;
    eval {
        my $host     = $Conf::mgrast_dbhost;
        my $database = $Conf::mgrast_db;
        my $user     = $Conf::mgrast_dbuser;
        my $password = $Conf::mgrast_dbpass;
        $dbh = DBI->connect(
            "DBI:Pg:dbname=$database;host=$host",
            $user,
            $password,
            { RaiseError => 1, AutoCommit => 0, PrintError => 0 }
        ) || die $DBI::errstr;
    };
    if ($@ || (! $dbh)) {
        warn "Unable to connect to metagenomics database: $@\n";
        return undef;
    }
    $dbh->{pg_expand_array} = 1;
    
    # create object
    my $self = {
        dbh     => $dbh,    # postgres analysis db handle
        chdl    => $chdl,   # cassnadra m5nr handle
        chunk   => 2000,    # max # md5s to query at once
        version => $version || $Conf::m5nr_annotation_version || 1  # m5nr version
    };
    bless $self, $class;
    return $self;
}

sub DESTROY {
   my ($self) = @_;
   if ($self->{dbh})  { $self->{dbh}->disconnect(); }
   if ($self->{chdl}) { $self->{chdl}->close(); }
}

sub dbh {
  my ($self) = @_;
  return $self->{dbh};
}

sub chdl {
  my ($self) = @_;
  return $self->{chdl};
}

sub chunk {
  my ($self) = @_;
  return $self->{chunk};
}

sub version {
  my ($self) = @_;
  return $self->{version};
}

sub get_where_str {
    my ($self, $items) = @_;
    
    my @text;
    unless ($items && (@$items > 0)) { return ""; }
    foreach my $i (@$items) {
        if ($i && ($i =~ /\S/)) {
            push @text, $i;
        }
    }
    if (@text == 1) {
        return " WHERE " . $text[0];
    } elsif (@text > 1) {
        return " WHERE " . join(" AND ", @text);
    } else {
        return "";
    }
}

sub execute_query {
    my ($self, $query) = @_;
    my $sth = $self->dbh->prepare($query);
    $sth->execute() || die "Couldn't execute statement: ".$sth->errstr;
    return $sth;
}

sub end_query {
    my ($self, $sth) = @_;
    $sth->finish;
    $self->dbh->commit;
}

sub all_job_abundances {
    my ($self, $job, $taxa, $org, $fun, $ont) = @_;
    
    my $tax = "";
    my $tax_map = {};
    my $org_map = {}; # tax_lvl => taxa => abundance
    my $fun_map = {}; # func => abundance
    my $ont_map = {}; # source => level1 => abundance
    my $ont_cat = {}; # source => ont => level1
        
    if ($org && $taxa && @$taxa) {
        if (scalar(@$taxa) == 1) {
            $tax = $taxa->[0];
            # org => taxa
            $tax_map = $self->chdl->get_org_taxa_map($tax);
            $org_map->{$tax} = {};
        } else {
            # org => [ taxa ]
            $tax_map = $self->chdl->get_taxa_hierarchy();
            foreach my $t (@$taxa) {
                $org_map->{$t} = {};
            }
        }
    }
    if ($ont) {
        $ont_cat = $self->chdl->get_ontology_hierarchy();
    }
    
    my $query = "SELECT md5, abundance FROM job_md5s WHERE version=".$self->version." AND job=".$job." AND exp_avg <= -5 AND ident_avg >= 60 AND len_avg >= 15";
    my $sth   = $self->execute_query($query);
    my $md5s  = {};
    my $count = 0;
    
    my $add_annotations = sub {
        my $data = $self->chdl->get_records_by_id([keys %$md5s]);
        foreach my $set (@$data) {
            if ($fun) {
                foreach my $f (@{$set->{function}}) {
                    unless (exists $fun_map->{$f}) {
                        $fun_map->{$f} = 0;
                    }
                    $fun_map->{$f} += $md5s->{$set->{id}};
                }
            }
            if ($ont && exists($ont_cat->{$set->{source}})) {
                unless (exists $ont_map->{$set->{source}}) {
                    $ont_map->{$set->{source}} = {};
                }
                foreach my $a (@{$set->{accession}}) {
                    unless (exists $ont_map->{$set->{source}}{ $ont_cat->{$set->{source}}{$a} }) {
                        $ont_map->{$set->{source}}{$ont_cat->{$set->{source}}{$a}} = 0;
                    }
                    $ont_map->{$set->{source}}{$ont_cat->{$set->{source}}{$a}} += $md5s->{$set->{id}};
                }
            }
            if ($org) {
                foreach my $o (@{$set->{organism}}) {
                    if ($tax) {
                        next if (($tax eq 'domain') && ($tax_map->{$o} =~ /other|unknown|unclassified/));
                        unless (exists $org_map->{$tax}{$tax_map->{$o}}) {
                            $org_map->{$taxa->[0]}{$tax_map->{$o}} = 0;
                        }
                        $org_map->{$taxa->[0]}{$tax_map->{$o}} += $md5s->{$set->{id}};
                    } else {
                        for (my $i=0; $i<scalar(@$taxa); $i++) {
                            next if (($taxa->[$i] eq 'domain') && ($tax_map->{$o}[$i] =~ /other|unknown|unclassified/));
                            unless (exists $org_map->{$taxa->[$i]}{$tax_map->{$o}[$i]}) {
                                $org_map->{$taxa->[$i]}{$tax_map->{$o}[$i]} = 0;
                            }
                            $org_map->{$taxa->[$i]}{$tax_map->{$o}[$i]} += $md5s->{$set->{id}};
                        }
                    }
                }
            }
        }
    };
    
    while (my @row = $sth->fetchrow_array()) {
        $md5s->{$row[0]} = $row[1];
        $count++;
        if ($count == $self->chunk) {
            $add_annotations->();
            $md5s = {};
            $count = 0;
        }
    }
    if ($count > 0) {
        $add_annotations->();
    }
    $self->end_query($sth);
    
    return ($org_map, $fun_map, $ont_map);
}

sub all_job_md5sums {
    my ($self, $job) = @_;
    my @md5s = ();
    my $sth  = $self->execute_query("SELECT m.md5 FROM md5s m, job_md5s j WHERE j.version=".$self->version." AND j.job=$job AND 'j.md5=m._id'");
    while (my @row = $sth->fetchrow_array()) {
        push @md5s, $row[0];
    }
    $self->end_query($sth);
    return \@md5s;
}

sub get_alpha_diversity {
    my ($self, $org_map) = @_;
    # org_map = taxa => abundance
    my $alpha = 0;
    my $h1    = 0;
    my $sum   = sum values %$org_map;
    
    unless ($sum) {
        return $alpha;
    }
    foreach my $num (values %$org_map) {
        my $p = $num / $sum;
        if ($p > 0) { $h1 += ($p * log(1/$p)) / log(2); }
    }
    $alpha = 2 ** $h1;
    
    return $alpha;
}

sub get_rarefaction_xy {
    my ($self, $org_map, $nseq) = @_;
    # org_map = taxa => abundance
    my $rare = [];
    my $size = ($nseq > 1000) ? int($nseq / 1000) : 1;
    my @nums = sort {$a <=> $b} values %$org_map;
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
