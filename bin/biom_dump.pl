#!/usr/bin/env perl

use strict;
use warnings;
no warnings('once');
use POSIX qw(strftime);

use Conf;
use WebServiceObject;
use MGRAST::Metadata;
use MGRAST::Analysis;
use Babel::lib::Babel;
use Digest::MD5 qw(md5_hex md5_base64);
use Data::Dumper;
use Getopt::Long;

my $output = "";
my $type   = "organism";
my $source = "";
my $rtype  = "";
my $glvl   = "";
my $eval   = undef;
my $ident  = undef;
my $alen   = undef;
my $fsrc   = "";
my @filter = ();
my $mgids  = "";
my $no_md  = 0;
my $usage  = q(
                       "annot_type=s"    => \$type,
    		           "source:s"        => \$source,
    		           "result_type:s"   => \$rtype,
    		           "group_level:s"   => \$glvl,
    		           "evalue:i"        => \$eval,
    		           "identity:i"      => \$ident,
    		           "length:i"        => \$alen,
    		           "filter:s"        => \@filter,
    		           'filter_source:s' => \$fsrc,
    		           'mgids:s'         => \$mgids,
	                   'no_metadata!'    => \$no_md,
    		           'output:s'        => \$output
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { die $usage; }
if ( ! GetOptions( "annot_type=s"    => \$type,
		           "source:s"        => \$source,
		           "result_type:s"   => \$rtype,
		           "group_level:s"   => \$glvl,
		           "evalue:i"        => \$eval,
		           "identity:i"      => \$ident,
		           "length:i"        => \$alen,
		           "filter:s"        => \@filter,
		           'filter_source:s' => \$fsrc,
		           'mgids:s'         => \$mgids,
		           'no_metadata!'    => \$no_md,
		           'output:s'        => \$output
                 ) )
  { die "missing parameters"; }

my @data = ();
if (-s $mgids) {
    @data = `cat $mgids`;
    chomp @data;
} elsif ($mgids) {
    @data = split(/,/, $mgids);
} else {
    die "need one or more metagenome ids";
}

$source = $source ? $source : (($type eq 'organism') ? 'M5NR' : (($type eq 'function') ? 'Subsystems': 'RefSeq'));
$rtype  = $rtype ? $rtype : 'abundance';
$glvl   = $glvl ? $glvl : (($type eq 'organism') ? 'strain' : 'function');
$eval   = defined($eval) ? $eval : 5;
$ident  = defined($ident) ? $ident : 60;
$alen   = defined($alen) ? $alen : 15;
$fsrc   = $fsrc ? $fsrc : (($type eq 'organism') ? 'Subsystems' : 'M5NR');
$no_md  = $no_md ? 1 : 0;

my $all_srcs  = {};
my $leaf_node = 0;
my $matrix_id = join("_", map {'mgm'.$_} sort @data).'_'.join("_", ($type, $glvl, $source, $rtype, $eval, $ident, $alen));
if (@filter > 0) {
    $matrix_id .= join("_", sort map { $_ =~ s/\s+/_/g } @filter)."_".$fsrc;
}

my $json = new JSON;
$json = $json->utf8();
$json->max_size(0);
$json->allow_nonref;

# initialize analysis obj with mgids
my ($master, $error) = WebServiceObject::db_connect();
my $mgdb = MGRAST::Analysis->new( $master->db_handle );
unless (ref($mgdb)) {
    die "Can't connect to database";
}
$mgdb->set_jobs(\@data);

# controlled vocabulary set
my $hierarchy = { organism => [ ['strain', 'bottom organism taxanomic level'],
			                         ['species', 'organism type level'],
			                         ['genus', 'organism taxanomic level'],
			                         ['family', 'organism taxanomic level'],
			                         ['order', 'organism taxanomic level'],
			                         ['class', 'organism taxanomic level'],
			                         ['phylum', 'organism taxanomic level'],
			                         ['domain', 'top organism taxanomic level'] ],
			           ontology => [ ['function', 'bottom function ontology level'],
                                     ['level3', 'function ontology level' ],
                                     ['level2', 'function ontology level' ],
                      	             ['level1', 'top function ontology level'] ]
                     };
my $sources = { organism => [ ["M5NR", "comprehensive protein database"],
                                   ["RefSeq", "protein database"],
	                               ["SwissProt", "protein database"],
	                               ["GenBank", "protein database"],
	                               ["IMG", "protein database"],
	                               ["SEED", "protein database"],
	                               ["TrEMBL", "protein database"],
	                               ["PATRIC", "protein database"],
	                               ["KEGG", "protein database"],
	                               ["M5RNA", "comprehensive RNA database"],
						           ["RDP", "RNA database"],
						           ["Greengenes", "RNA database"],
			                       ["LSU", "RNA database"],
		                           ["SSU", "RNA database"] ],
		             ontology => [ ["Subsystems", "ontology database, type function only"],
	                               ["NOG", "ontology database, type function only"],
				                   ["COG", "ontology database, type function only"],
				                   ["KO", "ontology database, type function only"] ]
		             };
my $result_idx = { abundance => {function => 3, organism => 10, feature => 2},
		           evalue    => {function => 5, organism => 12, feature => 3},
		           length    => {function => 7, organism => 14, feature => 5},
		           identity  => {function => 9, organism => 16, feature => 7}
    	         };
my $result_map = {abundance => 'abundance', evalue => 'exp_avg', length => 'len_avg', identity => 'ident_avg'};
my @func_hier  = map { $_->[0] } @{$hierarchy->{ontology}};
my @org_hier   = map { $_->[0] } @{$hierarchy->{organism}};
my $type_set   = ["function", "organism", "feature"];
    		         
# validate controlled vocabulary params
unless (exists $result_map->{$rtype}) {
    die "invalid result_type for matrix call: ".$rtype." - valid types are [".join(", ", keys %$result_map)."]";
}
if ($type eq 'organism') {
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('protein')};
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('rna')};
    if ( grep(/^$glvl$/, @org_hier) ) {
        $glvl = 'tax_'.$glvl;
        if ($glvl eq 'tax_strain') {
            $glvl = 'name';
 	        $leaf_node = 1;
        }
    } else {
        die "invalid group_level for matrix call of type ".$type.": ".$glvl." - valid types are [".join(", ", @org_hier)."]";
    }
} elsif ($type eq 'function') {
    map { $all_srcs->{$_->[0]} = 1 } grep { $_->[0] !~ /^GO/ } @{$mgdb->sources_for_type('ontology')};
    if ( grep(/^$glvl$/, @func_hier) ) {
        if ($glvl eq 'function') {
  	        $glvl = ($source =~ /^[NC]OG$/) ? 'level3' : 'level4';
        }
        if ( ($glvl eq 'level4') || (($source =~ /^[NC]OG$/) && ($glvl eq 'level3')) ) {
  	        $leaf_node = 1;
        }
    } else {
        die "invalid group_level for matrix call of type ".$type.": ".$glvl." - valid types are [".join(", ", @func_hier)."]";
    }
} elsif ($type eq 'feature') {
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('protein')};
    map { $all_srcs->{$_->[0]} = 1 } @{$mgdb->sources_for_type('rna')};
    delete $all_srcs->{M5NR};
    delete $all_srcs->{M5RNA};
}
unless (exists $all_srcs->{$source}) {
    die "invalid source for matrix call of type ".$type.": ".$source." - valid types are [".join(", ", keys %$all_srcs)."]";
}

# get data
my $org2tax = {};
my $md52id  = {};
my $ttype   = '';
my $mtype   = '';
my $matrix  = []; # [ row <annotation>, col <mgid>, value ]
my $col_idx = $result_idx->{$rtype}{$type};
my $umd5s   = [];

if ($type eq 'organism') {
    $ttype = 'Taxon';
    $mtype = 'taxonomy';
    if (@filter > 0) {
        $umd5s = $mgdb->get_md5s_for_ontology(\@filter, $fsrc);
    }
    unless ((@filter > 0) && (@$umd5s == 0)) {
        if ($leaf_node) {
            # my ($self, $md5s, $sources, $eval, $ident, $alen, $with_taxid) = @_;
            my (undef, $info) = $mgdb->get_organisms_for_md5s($umd5s, [$source], int($eval), int($ident), int($alen));
            # mgid, source, tax_domain, tax_phylum, tax_class, tax_order, tax_family, tax_genus, tax_species, name, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
            @$matrix = map {[ $_->[9], $_->[0], toNum($_->[$col_idx], $rtype) ]} @$info;
            map { $org2tax->{$_->[9]} = [ @$_[2..9] ] } @$info;
        } else {
            # my ($self, $level, $names, $srcs, $value, $md5s, $eval, $ident, $alen) = @_;
            @$matrix = map {[ $_->[1], $_->[0], toNum($_->[2], $rtype) ]} @{$mgdb->get_abundance_for_tax_level($glvl, undef, [$source], $result_map->{$rtype}, $umd5s, int($eval), int($ident), int($alen))};
            # mgid, hier_annotation, value
        }
    }
} elsif ($type eq 'function') {
    $ttype = 'Function';
    $mtype = 'ontology';
    if (@filter > 0) {
        $umd5s = $mgdb->get_md5s_for_organism(\@filter, $fsrc);
    }
    unless ((@filter > 0) && (@$umd5s == 0)) {
        if ($leaf_node) {
            # my ($self, $md5s, $source, $eval, $ident, $alen) = @_;
            my (undef, $info) = $mgdb->get_ontology_for_md5s($umd5s, $source, int($eval), int($ident), int($alen));
            # mgid, id, annotation, abundance, sub_abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv, md5s
            @$matrix = map {[ $_->[1], $_->[0], toNum($_->[$col_idx], $rtype) ]} @$info;
        } else {
            # my ($self, $level, $names, $src, $value, $md5s, $eval, $ident, $alen) = @_;
            @$matrix = map {[ $_->[1], $_->[0], toNum($_->[2], $rtype) ]} @{$mgdb->get_abundance_for_ontol_level($glvl, undef, $source, $result_map->{$rtype}, $umd5s, int($eval), int($ident), int($alen))};
            # mgid, hier_annotation, value
        }
    }
} elsif ($type eq 'feature') {
    $ttype = 'Gene';
    $mtype = $source.' ID';
    # my ($self, $md5s, $eval, $ident, $alen, $ignore_sk, $rep_org_src) = @_;
    my $info = $mgdb->get_md5_data(undef, int($eval), int($ident), int($alen), 1);
    # mgid, md5, abundance, exp_avg, exp_stdv, ident_avg, ident_stdv, len_avg, len_stdv
    my %md5s = map { $_->[1], 1 } @$info;
    my $mmap = $mgdb->decode_annotation('md5', [keys %md5s]);
    map { push @{$md52id->{ $mmap->{$_->[1]} }}, $_->[0] } @{ $mgdb->annotation_for_md5s([keys %md5s], [$source]) };
    @$matrix = map {[ $_->[1], $_->[0], toNum($_->[$col_idx], $rtype) ]} grep {exists $md52id->{$_->[1]}} @$info;
}

@$matrix = sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @$matrix;
my $row_ids = sorted_hash($matrix, 0);
my $col_ids = sorted_hash($matrix, 1);

# produce output
my $brows = [];
my $bcols = [];
my $r_map = ($type eq 'feature') ? $md52id : get_hierarchy($mgdb, $type, $glvl, $source, $leaf_node);
foreach my $rid (sort {$row_ids->{$a} <=> $row_ids->{$b}} keys %$row_ids) {
    my $rmd = exists($r_map->{$rid}) ? { $mtype => $r_map->{$rid} } : undef;
    push @$brows, { id => $rid, metadata => $rmd };
}
my $mddb = MGRAST::Metadata->new();
my $meta = $no_md ? {} : $mddb->get_jobs_metadata_fast(\@data, 1);
my $name = $mgdb->_name_map();
foreach my $cid (sort {$col_ids->{$a} <=> $col_ids->{$b}} keys %$col_ids) {
    my $cmd = exists($meta->{$cid}) ? $meta->{$cid} : undef;
    my $cnm = exists($name->{$cid}) ? $name->{$cid} : undef;
    push @$bcols, { id => 'mgm'.$cid, name => $cnm, metadata => $cmd };
}
    
my $obj = { "id"                   => $matrix_id,
	        "format"               => "Biological Observation Matrix 1.0",
  	        "format_url"           => "http://biom-format.org",
  	        "type"                 => $ttype." table",
  	        "generated_by"         => "MG-RAST revision ".$Conf::server_version,
  	        "date"                 => strftime("%Y-%m-%dT%H:%M:%S", localtime),
  	        "matrix_type"          => "sparse",
  	        "matrix_element_type"  => ($rtype eq 'abundance') ? "int" : "float",
  	        "matrix_element_value" => $rtype,
  	        "shape"                => [ scalar(keys %$row_ids), scalar(keys %$col_ids) ],
  	        "rows"                 => $brows,
  	        "columns"              => $bcols,
  	        "data"                 => index_sparse_matrix($matrix, $row_ids, $col_ids)
  	      };

unless ($output) {
    $output = md5_hex($obj->{id}).'.biom';
}
open(FILE, ">$output");
print FILE $json->encode($obj);
close FILE;
exit;

sub get_hierarchy {
    my ($mgdb, $type, $level, $src, $leaf_node) = @_;
    if ($type eq 'organism') {
        return $leaf_node ? $org2tax : $mgdb->get_hierarchy('organism', undef, undef, undef, $level);
    } elsif ($type eq 'function') {
        return $leaf_node ? $mgdb->get_hierarchy('ontology', $src) : $mgdb->get_hierarchy('ontology', $src, undef, undef, $level);
    } else {
        return {};
    }
}

sub index_sparse_matrix {
    my ($matrix, $rows, $cols) = @_;
    my $sparse = [];
    foreach my $pos (@$matrix) {
        my ($r, $c, $v) = @$pos;
        push @$sparse, [ $rows->{$r}, $cols->{$c}, $v ];
    }
    return $sparse;
}

sub sorted_hash {
    my ($array, $idx) = @_;
    my $pos = 0;
    my $out = {};
    my @sub = sort map { $_->[$idx] } @$array;
    foreach my $x (@sub) {
        next if (exists $out->{$x});
        $out->{$x} = $pos;
        $pos += 1;
    }
    return $out;
}

sub toFloat {
    my ($x) = @_;
    return $x * 1.0;
}

sub toNum {
    my ($x, $type) = @_;
    if ($type eq 'abundance') {
        return int($x);
    } else {
        return $x * 1.0;
    }
}
