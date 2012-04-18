package WebComponent::BlastForm;

# BlastForm - Form to input BLAST data and arguments

use FIG;
use strict;
use warnings;

use base qw( WebComponent );

1;


=pod
    
=head1 NAME

BlastForm - Form to input BLAST data and arguments

=head1 DESCRIPTION

WebComponent for a form in which to input BLAST data and arguments

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
    my $self = shift->SUPER::new(@_);
    
    $self->application->register_component('FilterSelect', 'OrganismSelectBlast');

    $self->{fig}    = undef;
    $self->{evalue} = 10;
    
    return $self;
}

=item * B<output> ()

Returns the html output of the BlastForm component.

=cut

sub output {
    my ($self) = @_;
    
    my $application = $self->application();
    my $fig = $application->data_handle('FIG');
    my $cgi = $application->cgi();
    
    # check if we have a valid fig
    unless ($fig) {
      $application->add_message('warning', 'Invalid organism id');
      return "";
    }

    unless ( defined($fig) ) {$self->application->add_message('warning', 'No data object passed'); return '';}

    # contruct introductory text
    my $html = "<div style='padding-left: 10px;'>";

    my $cutoff    = $cgi->param('evalue')   || 10;
    my $word_size = $cgi->param('wsize')    || 0;   # word size == 0 for default values
    my $filter    = $cgi->param('filter')   || 'F';

    # create select organism form
    $html .= $self->application->page->start_form( 'blast_form', { 'page' => 'BlastRun' } );
    $html .= "<table>";
    my $nuc_checked = "";
    my $aa_checked = " checked=checked";
    if ($cgi->param('seq_type') && $cgi->param('seq_type') eq 'aa') {
      $nuc_checked = " checked=checked";
      $aa_checked = "";
    }
    my $f_on_checked = "";
    my $f_off_checked = " checked=checked";
    if ($filter eq 'T') {
      $f_on_checked = " checked=checked";
      $f_off_checked = "";
    }
    $html .= "<tr><th>sequence</th><td><input type='radio' name='seq_type' value='nuc'$nuc_checked>nucleotide</td><td style='padding-right: 10px;'><input type='radio' name='seq_type' value='aa'$aa_checked>amino acid</td><th>filter</th><td><input type='radio' name='filter' value='F'$f_off_checked>off</td><td><input type='radio' name='filter' value='T'$f_on_checked>on</td></tr>\n";
    $html .= "<tr><th>cutoff</th><td colspan=2><input type='text' name='evalue' value='$cutoff' size=5>&nbsp;<i>(e.g.: 1e-30)</i></td><th>word size</th><td colspan=2><input type='text' name='wsize' value='$word_size' size=5>&nbsp;<i>(0 for default)</i></td></tr>";
    $html .= "</table>";

    $html .= "<textarea style='width: 550px;height: 150px;' name='fasta'>".($cgi->param('fasta') || "")."</textarea><br/>\n";

    # check if we have a predefined organism, in that case we don't need an 
    # organism select box
    if (defined($cgi->param('organism'))) {
      $html .= "<input type='hidden' name='organism' value='" . $cgi->param('organism') . "'>";
    } else {

      # create the organism select component
      my $organism_select_component = $self->application->component('OrganismSelectBlast');
      
      # get the list of public genomes
      my $genome_list = $fig->genome_list();
      
      # check for private organisms
      my $user = $application->session->user();
      if ($user) {
	
	my $orgs = $user->has_right_to(undef, 'view', 'genome');
	
	# get a rast master
	my $rast = $application->data_handle('RAST');
	
	if (ref($rast)) {

	  # if this is true, the user has at least one right concerning private organisms
	  if (scalar(@$orgs)) {
	    
	    # check if user has access to all organisms
	    if ($orgs->[0] eq '*') {
	      @$orgs = map { $_->genome_id() } @{$rast->Job->get_objects()};
	    }
	    
	    # there is at least one organism
	    if (scalar(@$orgs)) {
	      
	      my $orgs_done = {};
	      foreach my $org (@$orgs) {
		next unless $org;
		next if $orgs_done->{$org};
		$orgs_done->{$org} = 1;
		my $job = $rast->Job->get_objects( { genome_id => $org } );
		my $orgname = "";
		if (scalar(@$job)) {
		  $orgname = "Private: ".$job->[0]->genome_name();
		  push(@$genome_list, [$org, $orgname]);
		}
	      }
	    }
	  }
	}
      }
      
      my @sorted_genome_list = sort { (($b->[1] =~ /^Private\: /) <=> ($a->[1] =~ /^Private\: /)) || ($a->[1] cmp $b->[1]) } @$genome_list;
      my $org_values = [];
      my $org_labels = [];
      foreach my $line (@sorted_genome_list) {
	push(@$org_values, $line->[0]);
	push(@$org_labels, $line->[1]);
      }
      $organism_select_component->values( $org_values );
      $organism_select_component->labels( $org_labels );
      $organism_select_component->name('organism');
      $organism_select_component->width(550);
      $organism_select_component->multiple(1);
      
      $html .= "<p>\n";
      
      $html .= "Organism:<br>\n";
      $html .= $organism_select_component->output();
      
      $html .= "<p>\n";
    }

    $html .= "<br><input type='submit' name='act' class='button' value='BLAST'>&nbsp;&nbsp;&nbsp;<input type='reset' class='button' value='Clear'><p>&nbsp;<p>\n";

    $html .= $self->application->page->end_form();
    $html .= "</div>";    

    return $html;
}

sub evalue {
    my($self, $evalue) = @_;

    if ( defined($evalue) )
    {
	$self->{evalue} = $evalue;
    } 

    return $self->{evalue};
}

sub fig {
    my($self, $fig) = @_;

    if ( defined($fig) )
    {
	$self->{fig} = $fig;
    } 

    return $self->{fig};
}
