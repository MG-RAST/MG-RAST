package MGRAST::WebPage::MetagenomeFeatureList;

use base qw( WebPage );

use Conf;

use URI::Escape;

use strict;
use warnings;
use Tracer;
use HTML;

use MGRAST::MGRAST qw( get_menu_metagenome );

use Data::Dumper;
use FFs;

1;

=pod

=head1 NAME

FeatureList - an instance of WebPage which displays a table with a list of features

=head1 DESCRIPTION

Display a table with a list of features

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Features');
  $self->application->register_component('Table', 'feature_table');

  return 1;
}

=item * B<output> ()

Returns the html output of the Annotation page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  unless (defined($cgi->param('feature'))) {
    $application->add_message('warning', 'FeatureList page called without an identifier');
    return "";
  }

  my @ids = $cgi->param('feature');
  my $title = $cgi->param('title') || '';
  my $metagenome = $cgi->param('metagenome') || '';

  my $fig = $application->data_handle('FIG', $metagenome);

  # check if we have a valid fig
  unless ($fig) {
    $application->add_message('warning', 'Error in processing request');
    return "";
  }

  &get_menu_metagenome($self->application->menu, $metagenome, $self->application->session->user);

  my $table;
  if ( $ids[0] =~ /^fig\|(\d+\.\d+)\.([^\.]+)\.(\d+)/ )
  {
      $table = $self->feature_table(\@ids);
  }
  elsif ( $ids[0] =~ /^\S+_\d+_\d+$/ )
  {
      $table = $self->fragment_table($metagenome, \@ids);
  }

  my $html = "<span style='font-size: 1.6em'><b>$title</b></span>\n<p>" . $table->output;
  return $html;
}

sub feature_table {
    my($self, $ids) = @_;

    # SEED/RAST feature ids

    my $fig   = $self->application->data_handle('FIG');

    my(@ids, %org_name);
    foreach my $fid ( @$ids )
    {
	if ( $fid =~ /^fig\|(\d+\.\d+)\.([^\.]+)\.(\d+)/ )
	{
	    my($genome, $type, $num) = ($1, $2, $3);
	    if ( not exists $org_name{$genome} ) {
		$org_name{$genome} = $fig->org_of($fid);
	    }
	    
	    push @ids, [$fid, $genome, $type, $num, $org_name{$genome}];
	}
    }

    my $table_data = [];
    
    foreach my $rec ( sort {$a->[4] cmp $b->[4] or
				$a->[2] cmp $b->[2] or
				$a->[3] <=> $b->[3]} @ids )
    {
	my($fid, $genome, $type, $num, $orgname) = @$rec;
	
	my $link = qq(<a href="?page=Annotation&feature=$fid">$fid</a>);
	
	my $func;
	if ( $fig->is_real_feature($fid) )
	{
	    $func = scalar $fig->function_of($fid) || '';
	}
	else
	{
	    $func = 'DELETED FEATURE';
	}
	
	push @$table_data, [ 
			     $link,
			     $org_name{$genome},
			     $func,
			     ];
    }

    my $table = $self->application->component('feature_table');
    $table->show_export_button( { strip_html => 1 } );
    $table->columns( [ 
		       { name => 'Feature', sortable => 1, filter => 1, operator => 'like' },
		       { name => 'Genome', sortable => 1, filter => 1 },
		       { name => 'Function', sortable => 1, filter => 1 },
		       ] );

    $table->data( $table_data );

    return $table;
}

sub fragment_table {
    my($self, $metagenome, $ids) = @_;

    # mg-rast sequence ids -- contig_beg_end

    my $fig   = $self->application->data_handle('FIG', $metagenome);

    my $metagenome_name = $fig->genus_species($metagenome);
    $metagenome_name =~ s/_/ /g;

    my $features = $fig->all_features_detailed_fast($metagenome);

    # hack to get function format -- wantarray returns array now, should actually be a scalar
    my $func_type = ref($features->[0][6]);

    my $table_data = [];
    my %wanted = map {$_ => 1} @$ids; 
    foreach my $feature ( grep {exists $wanted{$_->[1]}} @$features )
    {
	my($fragment, $beg, $end) = ($feature->[1] =~ /^(\S+)_(\d+)_(\d+)$/);

	my $func = ''; 
	if ( $func_type eq 'ARRAY' ) {
	    $func = $feature->[6][1];
	} else {
	    $func = $feature->[6];
	}

	my $ln = abs($beg - $end) + 1;
	
	push @$table_data, [$fragment, $beg, $end, $ln, $metagenome_name, $func];
    }

    foreach my $rec ( sort {$a->[0] <=> $b->[0] or $a->[4] cmp $b->[4]} @$table_data )
    {
	my($fragment, $beg, $end) = @$rec;
	
	my $link = qq(<a href="?page=MetagenomeSequence&metagenome=$metagenome&sequence=$fragment&subseq_beg=$beg&subseq_end=$end">$fragment</a>);
	$rec->[0] = $link;
    }

    my $table = $self->application->component('feature_table');
    $table->show_export_button( { strip_html => 1 } );
    $table->columns( [ 
		       { name => 'Sequence', sortable => 1 },
		       { name => 'Begin' },
		       { name => 'End' },
		       { name => 'Length', sortable => 1 },
		       { name => 'Metagenome' },
		       { name => 'Function', sortable => 1, filter => 1 },
		       ] );

    $table->data( $table_data );

    return $table;
}
