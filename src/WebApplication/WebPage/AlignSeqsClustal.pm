package WebPage::AlignSeqsClustal;

use base qw( WebPage );

use Conf;

use URI::Escape;

use strict;
use warnings;

#use HTML;
use FIGgjo;        # colorize_roles, colorize_functions
use gjoalignment;  # align_with_clustal
use gjonewicklib;
use clustaltree;   # tree_with_clustal
use gjoseqlib;     # read_fasta, print_alignment_as_fasta
use BasicLocation;

use Data::Dumper;

1;

=pod

=head1 NAME

Annotation - an instance of WebPage which displays information about an Annotation

=head1 DESCRIPTION

Display information about an Annotation

=head1 METHODS

=over 4

 * B<init> ()

Called when the web page is instanciated.

=cut


my $max_n_diff = 1;     # Maximum number of exceptions to consensus
my $max_f_diff = 0.10;  # Maximum fraction exceptions to consensus
my $minblos    = 1;     # Minimum score to be called a conservative change

sub init {
  my ($self) = @_;

  $self->title( 'Alignment and Tree' );
  $self->application->register_component( 'Table', 'AnnoTable' );
  $self->application->register_component( 'Info', 'CommentInfo' );
  $self->application->register_component( 'RegionDisplay','ComparedRegions' );

  return 1;
}

#sub require_javascript {

#  return [ "$Conf::cgi_url/Html/showfunctionalroles.js" ];

#}

=item * B<output> ()

Returns the html output of the Annotation page.

=cut

sub output {
  my ( $self ) = @_;
  
  my $application = $self->application;
  $self->{ 'cgi' } = $application->cgi;
  $self->{ 'fig' } = $application->data_handle( 'FIG' );
  
  my $user;
  if ($application->session->user) {
    $user = $application->session->user;
    $self->{ 'seeduser' } = $user->login;
  }

  #################
  # Get sequences #
  #################

  my @seqs = $self->{ 'cgi' }->param( 'cds_checkbox' );
  unless ( scalar( @seqs ) ) {
    @seqs = $self->{ 'cgi' }->param( 'fid' );
  }
  
  ##############
  # parameters #
  ##############

  $self->{ 'align_format' } = $self->{ 'cgi' }->param( 'align_format' );
  $self->{ 'tree_format' }  = $self->{ 'cgi' }->param( 'tree_format' );
  $self->{ 'color_aln_by' } = $self->{ 'cgi' }->param( 'color_aln_by' ) || 'consensus';
  $self->{ 'seq_format' }   = $self->{ 'cgi' }->param( 'seq_format' ) || 'protein';

  if ( $self->{ 'seq_format' } eq 'pre' ) {
    my $firstp = $self->{ 'cgi' }->param( 'firstpoint' );
    my $secondp = $self->{ 'cgi' }->param( 'secondpoint' );
    if ( defined( $firstp ) && $firstp =~ /^-?\d+$/ ) {
      $self->{ 'seq_format' } .= "_$firstp";
    }
    if ( defined( $secondp ) && $secondp =~ /^-?\d+$/ ) {
      $self->{ 'seq_format' } .= "_$secondp";
    }
  }

  #########
  # TASKS #
  #########

  my $comment;

  my $action = $self->{ 'cgi' }->param( 'actionhidden' );
  if ( defined( $action ) && $action eq 'View Annotations' ) {
    return $self->viewAnnotations();
  }
  elsif ( defined( $action ) && $action eq 'Annotate' ) {
    $comment = $self->annotateTree();
  }
  elsif ( defined( $action ) && $action eq 'Reload' ) {
    $self->{ 'align_format' } = $self->{ 'cgi' }->param( 'Alignment' );
    $self->{ 'tree_format' }  = $self->{ 'cgi' }->param( 'Tree' );
    #$color_aln_by = $self->{ 'cgi' }->param( 'color_aln_by' ) || 'consensus';
    $self->{ 'seq_format' } = $self->{ 'cgi' }->param( 'Sequence' );
    if ( $self->{ 'seq_format' } eq 'pre' ) {
      my $firstp = $self->{ 'cgi' }->param( 'firstpoint' );
      my $secondp = $self->{ 'cgi' }->param( 'secondpoint' );
      if ( defined( $firstp ) && $firstp =~ /^-?\d+$/ ) {
	$self->{ 'seq_format' } .= "_$firstp";
      }
      if ( defined( $secondp ) && $secondp =~ /^-?\d+$/ ) {
	$self->{ 'seq_format' } .= "_$secondp";
      }
    }
  }
  elsif ( defined( $action ) && $action eq 'Align' ) {
    my @checked = $self->{ 'cgi' }->param( 'checked' );
    @seqs = ();
    foreach my $cb ( @checked ) {
      if ( $cb =~ /^checked_(fig.*)/ ) {
	push @seqs, $1;
      }
    }
  }
  elsif ( defined( $action ) && $action eq 'ShowRegions' ) {
    my @checked = $self->{ 'cgi' }->param( 'checked' );
    @seqs = ();
    my @genomes;
    foreach my $cb ( @checked ) {
      if ( $cb =~ /^checked_(fig.*)/ ) {
	push @seqs, $1;
	push @genomes, $self->{ 'fig' }->genome_of( $1 );
      }
    }
  
    my $regdisp = $self->application->component( 'ComparedRegions' );
    my $genome_number = scalar( @genomes );
    
    $regdisp->focus( $seqs[0] );
    $regdisp->show_genomes( \@genomes );
    $regdisp->number_of_regions( $genome_number );
#    $regdisp->add_features( $add_features );
    $regdisp->fig( $self->{ 'fig' } );
    my $regdispout = $regdisp->output();
    
    return $regdisp->output();
  }

  
  my @nseqs = ();
  foreach my $key ( @seqs ) {
    if ( $key =~ /cds_checkbox_(.*)/ ) {
      $key = $1;
    }
    push @nseqs, $key;
  }

  @seqs = @nseqs;
  
  my %seen;

  my @seqsTA;

  if ( $self->{ 'seq_format' } eq 'DNA' ) {
    @seqsTA = grep { $_->[2] }
      map  { [ $_, '', $self->{ 'fig' }->get_dna_seq( $_ ) ] }
	grep { ! $seen{ $_ }++ }
	  @seqs;
  }
  elsif ( $self->{ 'seq_format' } =~ /^pre_(-?\d+)_(-?\d+)/ ) {
    my $before = $1;
    my $after = $2;
    @seqsTA = grep { $_->[2] }
      map  { [ $_, '', $self->get_flanking( $_, $before, $after ) ] }
	grep { ! $seen{ $_ }++ }
	  @seqs;
  }
  else {
    @seqsTA = grep { $_->[2] }
      map  { [ $_, '', $self->{ 'fig' }->get_translation( $_ ) ] }
	grep { ! $seen{ $_ }++ }
	  @seqs;
  }

  @seqs = map { $_->[0] } @seqsTA;

  my %orgs = map { $_ => $self->{ 'fig' }->org_of( $_ ) || '' } @seqs;
  $self->{ 'orgs' } = \%orgs;

  my @tbl_data;
  foreach my $fid ( @seqs ) {
    my $func = $self->{ 'fig' }->function_of( $fid, $self->{ 'seeduser' } ) || "";
    $func =~ s/ +;/;/g;              # An ideosyncracy of some assignments
    $self->{ 'fid_func' }->{ $fid } = $func;
    push @tbl_data, [ $fid, $orgs{ $fid }, $func ];
  }
  
  ############################
  # construct the anno table #
  ############################
  my $annotable = $self->application->component( 'AnnoTable' );
  $annotable->columns( [ { name => 'ID', filter => 1, sortable => 1 },
			 { name => 'Organism', filter => 1, sortable => 1 },
			 { name => 'Annotation', filter => 1, sortable => 1 },		       
		       ] );
  $annotable->data( \@tbl_data );
  $annotable->show_top_browse( 1 );
  $annotable->show_select_items_per_page( 1 );
  $annotable->items_per_page( 10 );

  ###########################
  # construct the alignment #
  ###########################
  my @align = gjoalignment::align_with_clustal( \@seqsTA );
  my $alignmentcont;
  
  if ( @align ) {
    if ( $self->{ 'align_format' } eq "fasta" ) {
      $alignmentcont = "<pre>" . 
	join( "", map { my $tseq = $_->[2]; 
			$tseq =~ s/(.{1,60})/$1\n/g; 
			">$_->[0] $_->[1]\n$tseq" 
		      } @seqsTA ) .
			"</pre>\n";
    }
    elsif ( $self->{ 'align_format' } eq "clustal" ) {
      my $clustal_alignment = &to_clustal( \@align );
      $alignmentcont = "<pre>\n$clustal_alignment</pre>\n";
    }
    elsif ( $self->{ 'align_format' } eq "special" ) {
      $alignmentcont = $self->gjoalignment( \@align, \@seqs, $self->{ 'color_aln_by' } );
    }
    else {
      $alignmentcont = undef;
    }
  }
  
  ######################
  # construct the tree #
  ######################

  my $tree = clustaltree::tree_with_clustal( \@align );
  my $treecont;
  if ( defined( $self->{ 'tree_format' } ) && $self->{ 'tree_format' } eq 'newick' ) {
    $treecont .= &gjonewicklib::formatNewickTree( $tree );
  }
  elsif ( defined( $self->{ 'tree_format' } ) && $self->{ 'tree_format' } eq 'normal' ) {    
    $treecont = $self->construct_tree( \@seqs, $tree );
  }
  else {
    $treecont = undef;
  }

  ################
  # Hiddenvalues #
  ################

  my $hiddenvalues;
  $hiddenvalues->{ 'actionhidden' } = '';
  $hiddenvalues->{ 'align_format' } = $self->{ 'align_format' };
  $hiddenvalues->{ 'tree_format' } = $self->{ 'tree_format' };
  $hiddenvalues->{ 'color_aln_by' } = $self->{ 'color_aln_by' };
  $hiddenvalues->{ 'seq_format' } = $self->{ 'seq_format' };

  my $content = qq~<script>

function submitPage ( variablesubmit ) {

   document.getElementById( 'actionhidden' ).value = variablesubmit;
   document.getElementById( 'form' ).submit();

}

function checkAll ( element, second ) {
  var field = document.getElementsByName( element );
  for ( i = 0; i < field.length; i++ ) {
    if ( second ) {
      var tmp = "role##-##" + second;
      var hallo = field[i].id.indexOf( tmp );
      if ( hallo == 0 ) {
	field[i].checked = true ;
      }
    }
    else {
      field[i].checked = true ;
    }
  }
}

function checkFirst ( element )
{
  var field = document.getElementsByName( element );
  for ( i = 0; i < field.length/2; i++ ) {
    field[i].checked = true;
  }
}

function checkSecond ( element )
{
  var field = document.getElementsByName( element );
  for ( i= Math.round( field.length/2 ); i < field.length; i++ ) {
    field[i].checked = true ;
  }
}

function uncheckAll ( element, second )
{
  var field = document.getElementsByName( element );
  for ( i = 0; i < field.length; i++ ) {
    if ( second ) {
      var tmp = "role##-##" + second;
      var hallo = field[i].id.indexOf( tmp );
      if ( hallo == 0 ) {
	field[i].checked = false ;
      }
    }
    else {
      field[i].checked = false ;
    }
  }
}
</script>~;

  ####################
  # Display comments #
  ####################

  if ( defined( $comment ) && $comment ne '' ) {
    my $info_component = $self->application->component( 'CommentInfo' );
    
    $info_component->content( $comment );
    $info_component->default( 0 );
    $content .= $info_component->output();
  }

  ###########
  # CONTENT #
  ###########

  $content .= $self->start_form( 'form', $hiddenvalues );
  $content .= "<H1>Protein table</H1>\n";
  $content .= "<P>This table shows the proteins for which an alignment / tree will be displayed on this page.</P>";
  $content .= $annotable->output();
  $content .= "<BR><BR>";
  $content .= $self->get_actions( \@seqs );

  if ( defined( $alignmentcont ) ) {
    $content .= "<H1>Alignment: ". $self->{ 'align_format' }."</H1>";
    $content .= "<P>This part shows the alignment of the features. The alignment format is ";
    $content .= $self->{ 'align_format' };
    $content .= ". Currently, you can see an alignment of ";
    if ( $self->{ 'seq_format' } eq 'protein' ) {
      $content .= "the protein sequences of the features.";
    }
    elsif ( $self->{ 'seq_format' } eq 'DNA' ) {
      $content .= "the DNA sequences of the features.";
    }
    else {
      $content .= "the DNA sequences of downstream of the features.";
    }
    $content .= "</P>";
    $content .= $alignmentcont;
  }
  if ( defined( $treecont ) ) {
    $content .= "<H1>Neighbor-joining Tree of Selected Proteins</H1>";
    $content .= $treecont;
  }
  $content .= $self->end_form();
  
  return $content;
}

sub to_clustal {
  my ( $alignment ) = @_;
  
  my ( $tuple,$seq,$i );
  my $len_name = 0;
  foreach $tuple ( @$alignment ) {
    my $sz = length($tuple->[0]);
    $len_name = ($sz > $len_name) ? $sz : $len_name;
  }
  
  my @seq  = map { $_->[2] } @$alignment;
  my $seq1 = shift @seq;
  my $cons = "\377" x length($seq1);
  foreach $seq (@seq) {
    $seq  = ~($seq ^ $seq1);
    $seq  =~ tr/\377/\000/c;
    $cons &= $seq;
  }
  $cons =~ tr/\000/ /;
  $cons =~ tr/\377/*/;
  
  push(@$alignment,["","",$cons]);
  
  my @out = ();
  for ($i=0; ($i < length($seq1)); $i += 50) {
    foreach $tuple (@$alignment) {      
      my($id,undef,$seq) = @$tuple;
      my $line = sprintf("%-" . $len_name . "s",$id) . " " . substr($seq,$i,50) . "\n";
      push(@out,$line);
    }
    push(@out,"\n");
  }
  return join("","CLUSTAL W (1.8.3) multiple sequence alignment\n\n\n",@out);
}


sub construct_tree {

  my ( $self, $checkedarr, $tree ) = @_;

  my @checked = @$checkedarr;
  my $user = $self->{ 'seeduser' };
  my $peg_id    = $self->{ 'cgi' }->param( 'fid' );

  my %formatted_func = &FIGgjo::colorize_roles( $self->{ 'fid_func' } );
  
  my $html;
  $html .= join( "\n",
#		 $self->start_form( -method => 'post',
#				    -target => 'window$$',
#				    -action => 'fid_checked.cgi',
#				    -name   => 'fid_checked'
#				  ),
		 $self->{ 'cgi' }->hidden(-name => 'fid',          -value => $peg_id),
#		 $cgi->hidden(-name => 'SPROUT',       -value => $sprout),
#		 $cgi->hidden(-name => 'user',         -value => $user),
		 $self->{ 'cgi' }->hidden(-name => 'color_aln_by', -value => 'consensus'),
		 ""
	       );
  
  #------------------------------------------------------------------
  #  Build checkboxes and radio buttons for appropriate sequences:
  #------------------------------------------------------------------
  
  my @translatable = grep { $self->{ 'fig' }->translatable( $_ ) } @checked;
  
  my %check = map { $_ => qq(<input type=checkbox name=checked value="checked_$_">) }
    @translatable;
  
  my %from;
  if ( $user ) {
    %from = map { m/value=\"([^\"]+)\"/; $1 => $_ }
      $self->{ 'cgi' }->radio_group( -name     => 'from',
			 -nolabels => 1,
			 -override => 1,
			 -values   => [ @translatable ],
			 -default  => $peg_id
		       );
  }
  
  #------------------------------------------------------------------
  #  Aliases
  #------------------------------------------------------------------
  
  my %alias = map  { $_->[0] => $_->[1] }
    grep { $_->[1] }
      map  { [ $_, scalar $self->{ 'fig' }->feature_aliases( $_ ) ] }
	@checked;
  
  #------------------------------------------------------------------
  #  Formulate the desired labels:
  #------------------------------------------------------------------
  
  my %labels;
  foreach my $fid ( @checked ) {
    my @label;
    push @label, "<A HREF='?page=Annotation&feature=$fid'>$fid</A>";
    push @label, "[ $self->{ 'orgs' }->{ $fid } ]"                      if $self->{ 'orgs' }->{ $fid };
    push @label, $check{ $fid }                       if $check{ $fid };
    push @label, $from{ $fid }                        if $from{ $fid };
    push @label, $formatted_func{ $self->{ 'fid_func' }->{ $fid } } if $self->{ 'fid_func' }->{ $fid };
    push @label, html_esc( $alias{ $fid } )           if $alias{ $fid };
    
    $labels{ $fid } = join( ' ', @label );
  }
  
  #------------------------------------------------------------------
  #  Relabel the tips, midpoint root, pretty it up and draw
  #  the tree as printer plot
  #
  #  Adjustable parameters on text_plot_newick:
  #
  #     @lines = text_plot_newick( $node, $width, $min_dx, $dy )
  #------------------------------------------------------------------
  
  my $tree2  = newick_relabel_nodes( $tree, \%labels );
  my $tree3  = reroot_newick_to_approx_midpoint_w( $tree2 );
  my $tree4  = aesthetic_newick_tree( $tree3 );
  $html .= join( "\n",
		 '<PRE>',
		 text_plot_newick( $tree4, 80, 2, 2 ),
		 '</PRE>',
		 ''
	       );
  
  #------------------------------------------------------------------
  # RAE Add the check all/uncheck all boxes.
  #------------------------------------------------------------------
  
  my $checkall    = "<INPUT TYPE=BUTTON name='CheckAll' value='Check All' onclick='checkAll( \"checked\" )'>\n";
  my $checkfirst  = "<INPUT TYPE=BUTTON name='CheckFirst' value='Check First Half' onclick='checkFirst( \"checked\" )'>\n";
  my $checksecond = "<INPUT TYPE=BUTTON name='CheckSecond' value='Check Second Half' onclick='checkSecond( \"checked\" )'>\n";
  my $uncheckall  = "<INPUT TYPE=BUTTON name='UnCheckAll' value='Uncheck All' onclick='uncheckAll( \"checked\" )'>\n";

  my $viewAnnotations = "<INPUT TYPE=BUTTON name='ViewAnnotations' value='View Annotations' onclick='submitPage( \"View Annotations\" )'>\n";
  my $annotateButton = "<INPUT TYPE=BUTTON name='Annotate' value='Annotate' onclick='submitPage( \"Annotate\" )'>\n";
  my $alignButton = "<INPUT TYPE=BUTTON name='Align' value='Align' onclick='submitPage( \"Align\" )'>\n";
  my $showRegions = "<INPUT TYPE=BUTTON name='ShowRegions' value='Show Regions' onclick='submitPage( \"ShowRegions\" )'>\n";

  $html .= "<TABLE><TR><TD><B>Select:</B></TD><TD>$checkall</TD><TD>$checkfirst</TD><TD>$checksecond</TD><TD>$uncheckall</TD></TR></TABLE><BR>";

#  $html .= "<TABLE><TR><TD><B>Action:</B></TD><TD>$viewAnnotations</TD><TD>$annotateButton</TD><TD>$alignButton</TD><TD>$showRegions</TD></TR></TABLE><BR>";
  $html .= "<TABLE><TR><TD><B>Action:</B></TD><TD>$viewAnnotations</TD><TD>$annotateButton</TD><TD>$alignButton</TD></TR></TABLE><BR>";
  
#  $html .= join("\n",
#		"For selected (checked) sequences: "
#		, $self->{ 'cgi' }->submit('align'),
#		, $self->{ 'cgi' }->submit('view annotations')
#		, $self->{ 'cgi' }->submit('show regions')
#		, $self->{ 'cgi' }->br
#		, ""
#	       );
  
  if ( $self->{ 'seeduser' } ) {  
#    $html .= $self->{ 'cgi' }->submit('assign/annotate') . "\n";
    
    if ( $self->{ 'cgi' }->param('translate')) {
      $html .= join("\n",
		    , $self->{ 'cgi' }->submit('add rules')
		    , $self->{ 'cgi' }->submit('check rules')
		    , $self->{ 'cgi' }->br
		    , ''
		   );
    }
    
#    $html .= join( "\n", $self->{ 'cgi' }->br,
#		   "<a href='Html/help_for_assignments_and_rules.html'>Help on Assignments, Rules, and Checkboxes</a>",
#		   ""
#		 );
  }
  
#  $html .= $cgi->end_form . "\n";
  
  #  'align' with less than 2 sequences checked
  
  return $html;
}


sub gjoalignment {

  my ( $self, $alg, $check, $color_aln_by ) = @_;
  my ( $align2, $legend );
  my @align = @$alg;
  my @checked = @$check;

  #  Color by residue type:
  
  if ( $color_aln_by eq 'residue' ) {
    my %param1 = ( align => \@align, protein => 1 );
    $align2 = color_alignment_by_residue( \%param1 );
  }
  
  #  Color by consensus:
  
  else {
    my %param1 = ( align => \@align );
    ( $align2, $legend ) = color_alignment_by_consensus( \%param1 );
  }
  
  #  Add organism names:
  
  foreach ( @$align2 ) { $_->[1] = $self->{ 'orgs' }->{ $_->[0] } }
  
  #  Build a tool tip with organism names and functions:
  
  my %tips = map { $_ => [ $_, join( '<HR>', $self->{ 'orgs' }->{ $_ }, $self->{ 'fid_func' }->{ $_ } ) ] } @checked;
  $tips{ 'Consen1' } = [ 'Consen1', 'Primary consensus residue' ];
  $tips{ 'Consen2' } = [ 'Consen2', 'Secondary consensus residue' ];
  
  my %param2 = ( align   => $align2,
		 ( $legend ? ( legend  => $legend ) : () ),
		 tooltip => \%tips
	       );
  
  my $alignment = join( "\n",
			 scalar alignment_2_html_table( \%param2 ), "<BR>"
		       );
  
  return $alignment;
}

sub color_alignment_by_residue {
    my $align = shift if ( ref($_[0]) eq 'ARRAY' );

    my %data = ( ref( $_[0] ) eq 'HASH' ) ? %{ $_[0] } : @_;
    foreach ( keys %data ) { $data{ canonical_key( $_ ) } = $data{ $_ } }

    $align ||= $data{ align } || $data{ alignment };
    if ( ! $align || ( ref( $align ) ne 'ARRAY' ) )
    {
        print STDERR "color_alignment_by_residue called without alignment\n";
        return ();
    }

    my $colors = $data{ color };
    if ( $colors && ( ref( $colors ) eq 'HASH' ) )
    {
        print STDERR "color_alignment_by_residue called without invalid colors hash\n";
        return ();
    }

    if ( ! $colors )
    {
        my $is_prot = defined( $data{ protein } ) ? $data{ protein } : &guess_prot( $align );
        my $pallet = $data{ pallet };
        $colors = $is_prot ? aa_colors( $pallet ) : nt_colors( $pallet );
    }

    my ( $id, $def, $seq );
    my $pad_char = $data{ padchar } || $data{ pad } || ' ';
    my $reg1 = qr/^([^A-Za-z.*]+)/;
    my $reg2 = qr/([^A-Za-z.*]+)$/;
    my @colored_align = ();

    foreach ( @$align )
    {
        ( $id, $def, $seq ) = @$_;
        $seq =~ s/$reg1/$pad_char x length($1)/e;
        $seq =~ s/$reg2/$pad_char x length($1)/e;
        push @colored_align, [ $id, $def, scalar color_sequence( $seq, $colors ) ];
    }

    my @legend = ();  #  Need to create this still
    if ( wantarray )
    {
        my ( $i, $chr );
        my @row = ();
        foreach ( $i = 32; $i < 127; $i++ )
        {
            $chr = chr( $i );
            push @row, [ $chr, $colors->{$chr} || '#fff' ];
            if ( $i % 32 == 31 ) { push @legend, [ @row ]; @row = () }
        }
        push @legend, [ @row ];
    }

    wantarray ? ( \@colored_align, \@legend ) : \@colored_align;
}

sub color_alignment_by_consensus {
    my $align;
    $align = shift if ( ref($_[0]) eq 'ARRAY' );

    #  Options, with canonical form of keys

    my %data = ( ref( $_[0] ) eq 'HASH' ) ? %{ $_[0] } : @_;
    foreach ( keys %data ) { $data{ canonical_key( $_ ) } = $data{ $_ } }

    $align ||= $data{ align } || $data{ alignment };
    if ( ! $align || ( ref( $align ) ne 'ARRAY' ) )
    {
        print STDERR "color_alignment_by_consensus called without alignment\n";
        return ();
    }

    my ( $pallet, $legend ) = consensus_pallet( $data{ color } );

    my $conserve_list = conservative_change_list( \%data );
    my $conserve_hash = conservative_change_hash( \%data );

    my $chars = qr/^[-*A-Za-z]$/;

    my $s;
    my $pad_char = $data{ padchar } || $data{ pad } || ' ';
    my $reg1 = qr/^([^A-Za-z.*]+)/;
    my $reg2 = qr/([^A-Za-z.*]+)$/;

    my @seq = map { $s = uc $_->[2];
                    $s =~ s/$reg1/$pad_char x length($1)/e;
                    $s =~ s/$reg2/$pad_char x length($1)/e;
                    $s
                  }
              @$align;

    #  Define the consensus type(s) for each site.  There are a 3 options:
    #    1. There is a single consensus nucleotide.
    #    2. Two residue types are sufficient to describe the position.
    #    3. A residue and conservative changes are sufficient.

    my $len = length( $seq[0] );

    $max_n_diff = $data{ maxndiff } if defined( $data{ maxndiff } );
    $max_f_diff = $data{ maxfdiff } if defined( $data{ maxfdiff } );

    my @col_clr;              #  An array of hashes, one for each column
    my $cons1 = ' ' x $len;   #  Primary consensus characters
    my $cons2 = ' ' x $len;   #  Secondary consensus characters

    my ( $i, %cnt, $chr, @c, $min_consen, $c1, $c2, $clr );

    for ( $i = 0; $i < $len; $i++)
    {
        #  Count the number of each residue type in the column

        %cnt = ();
        foreach ( @seq ) { $chr = substr($_,$i,1); $cnt{$chr}++ if $chr =~ /$chars/ }

	my @harr = map { $cnt{$_} } keys %cnt;
	
	my $n_signif = 0;
	foreach my $n ( @harr ) {
	  $n_signif += $n;
	}
	  
#        $n_signif = sum( map { $cnt{$_} } keys %cnt );
        $min_consen = $n_signif - max( $max_n_diff, int( $max_f_diff * $n_signif ) );

        ( $c1, $c2, @c ) = consensus_residues( \%cnt, $min_consen, $conserve_hash );

        substr( $cons1, $i, 1 ) = $c1 if $c1;
        substr( $cons2, $i, 1 ) = $c2 if $c2;
        push @col_clr, consensus_colors( $pallet, $conserve_list, $c1, $c2, @c );
    }

    my @color_align = ();
#    my ( $id, $def, $seq );
    foreach ( @$align, [ 'Consen1', 'Primary consensus',   $cons1 ],
                       [ 'Consen2', 'Secondary consensus', $cons2 ]
            )
    {
        my ( $id, $def, $seq ) = @$_;
	if ( $id =~ /^fig/ ) {
	  $id = "<A HREF='?page=Annotation&feature=$id'>$id</A>";
	}

        $seq =~ s/^([^A-Za-z.]+)/$pad_char x length($1)/e;
        $seq =~ s/([^A-Za-z.]+)$/$pad_char x length($1)/e;

        $i = 0;
        my @clr_seq = map { [ $_, $col_clr[$i++]->{$_} || '#fff' ] }
                      split //, $seq;
        push @color_align, [ $id, $def, \@clr_seq ];
    }

    wantarray ? ( \@color_align, $legend ) : \@color_align;
}

#-------------------------------------------------------------------------------
#  A canonical key is lower case, has no underscores, and no terminal s
#
#     $key = canonical_key( $key )
#-------------------------------------------------------------------------------
sub canonical_key { 
  my $key = lc shift; 
  $key =~ s/_//g; 
  $key =~ s/s$//; 
  return $key ;
}

sub alignment_2_html_table
{
    my $align;
    $align = shift if ( ref($_[0]) eq 'ARRAY' );

    #  Options, with canonical form of keys

    my %options = ( ref( $_[0] ) eq 'HASH' ) ? %{ $_[0] } : @_;
    foreach ( keys %options ) { $options{ canonical_key( $_ ) } = $options{ $_ } }

    $align ||= $options{ align } || $options{ alignment };
    if ( ! $align || ( ref( $align ) ne 'ARRAY' ) )
    {
        print STDERR "alignment_2_html_table called without alignment\n";
        return '';
    }

    my $tooltip = $options{ tooltip } || $options{ popup } || 0;
    my $tiplink = '';

    my $nojavascript = $options{ nojavascript } || ( $tooltip ? 0 : 1 );

    my @html;
    push @html, "<TABLE Col=3>\n";
    foreach ( @$align )
    {
        if ( $tooltip )
        {
            #  Default tooltip is the id and description, but user can supply a
            #  hash with alternative mouseover parameters:
            #
            #     mouseover( $ttl, $text, $menu, $parent, $ttl_color, $text_color )
            #
            my @args;
            if ( ( ref( $tooltip ) eq 'HASH' )
              && ( ref( $tooltip->{ $_->[0] } ) eq 'ARRAY' )
               )
            {
                @args = @{ $tooltip->{ $_->[0] } }
            }
            else
            {
                @args = ( $_->[0], ( $_->[1] || ' ' ) );
            }
#            $tiplink = '<A' . &mouseover( @args ) . '>';
        }

        push @html, "  <TR>\n",
                    "    <TD NoWrap>$_->[0]</TD>\n",
 #                   "    <TD NoWrap>$_->[1]</TD>\n",
                    "    <TD><Pre>",
                             ( $tooltip ? $tiplink : () ),
                             sequence_2_html( $_->[2] ),
                             ( $tooltip ? '</A>' : () ),
                             "</Pre></TD>\n",
                    "  </TR>\n";
    }
    push @html, "</TABLE>\n";

    my $legend = $options{ key } || $options{ legend };
    if ( ref( $legend ) eq 'ARRAY' )
    {
        push @html, "<BR />\n", "<TABLE Col=1>\n";
        foreach ( @$legend )
        {
            push @html, "  <TR><TD><Pre><Big>",
                           sequence_2_html( $_ ),
                           "</Big></Pre></TD></TR>\n";
        }
        push @html, "</TABLE>\n";
    }

#    my $javascript = $nojavascript ? '' : &mouseover_JavaScript();
    my $javascript = $nojavascript;

    wantarray && $javascript ? ( join( '', @html ), $javascript )  #  ( $html, $script )
                             :   join( '', $javascript, @html );   #    $html
}

sub sequence_2_html
{
    return $_[0] if ref( $_[0] ) ne 'ARRAY';

    my $string = shift;
    my @html = ();
    my ( $txt, $clr );
    foreach ( @{ merge_common_color( $string ) } )
    {
        $txt = html_esc( $_->[0] );
        $txt or next;
        $clr = $_->[1];
        push @html, ( $clr ? qq(<span style="background-color:$clr">$txt</span>)
                           : $txt
                    )
    }
    join '', @html;
}

sub merge_common_color
{
    return $_[0] if ref( $_[0] ) ne 'ARRAY';

    my @string = ();
    my $color  = '';
    my @common_color = ();
    foreach ( @{ $_[0] }, [ '', 0 ] )  # One bogus empty string to flush it
    {
        if ( $_->[1] ne $color )
        {
            push @string, [ join( '', @common_color ), $color ],
            @common_color = ();
            $color = $_->[1]
        }
        push @common_color, $_->[0];
    }
    return \@string;
}

sub consensus_pallet
{
    #  Initialize with a standard set, ensuring that all keys are covered:

    my %pallet = ( ''       => '#fff',
                   other    => '#fff',
                   consen1  => '#bdf', consen1g => '#def',
                   positive => '#6e9',
                   consen2  => '#ee4', consen2g => '#eea',
                   mismatch => '#f9f'
                 );

    #  Overwrite defaults with user-supplied colors

    if ( ref($_[0]) eq 'HASH' )
    {
        my %user_pallet = %{ $_[0] };
        foreach ( keys %user_pallet ) { $pallet{ $_ } = $user_pallet{ $_ } }
    }

    my @legend;
    if ( wantarray )
    {
        @legend = ( [ [ 'Consensus 1'             => $pallet{ consen1  } ],
                      [ ' (when a gap)'           => $pallet{ consen1g } ] ],

                    [ [ 'Conservative difference' => $pallet{ positive } ] ],

                    [ [ 'Consensus 2'             => $pallet{ consen2  } ],
                      [ ' (when a gap)'           => $pallet{ consen2g } ] ],

                    [ [ 'Nonconservative diff.'   => $pallet{ mismatch } ] ],

                    [ [ 'Other character'         => $pallet{ ''       } ] ],
                  );
    }

    wantarray ? ( \%pallet, \@legend ) : \%pallet;
}

sub conservative_change_list
{
    my %options = ( ref( $_[0] ) eq 'HASH' ) ? %{ $_[0] } : @_;
    foreach ( keys %options ) { $options{ canonical_key( $_ ) } = $options{ $_ } }

    my $min_score = defined( $options{ minscore } ) ? $options{ minscore } : 1;

    my $matrix = ( ref( $options{ matrix } ) eq 'HASH' ) ? $options{ matrix }
                                                         : blosum62_hash_hash();

    my %hash;
    foreach ( keys %$matrix )
    {
        my $score = $matrix->{ $_ };
        $hash{ $_ } = [ grep { $score->{ $_ } >= $min_score } keys %$score ];
    }
    return \%hash;
}

sub conservative_change_hash
{
    my %options = ( ref( $_[0] ) eq 'HASH' ) ? %{ $_[0] } : @_;
    foreach ( keys %options ) { $options{ canonical_key( $_ ) } = $options{ $_ } }

    my $min_score = defined( $options{ minscore } ) ? $options{ minscore } : 1;

    my $matrix = ( ref( $options{ matrix } ) eq 'HASH' ) ? $options{ matrix }
                                                         : blosum62_hash_hash();

    my %hash;
    foreach ( keys %$matrix )
    {
        my $score = $matrix->{ $_ };
        $hash{ $_ } = { map  { $_ => 1 }
                        grep { $score->{ $_ } >= $min_score }
                        keys %$score
                      };
    }

    return \%hash;
}

sub blosum62_hash_hash
{
    my ( $aa_list, $raw_scores ) = raw_blosum62();
    my %hash;
    my @scores = @$raw_scores;
    foreach ( @$aa_list )
    {
        my @scr = @{ shift @scores };
        $hash{ $_ } = { map { $_ => shift @scr } @$aa_list };
    }
    return \%hash;
}

sub raw_blosum62
{
    return ( [ qw( A  R  N  D  C  Q  E  G  H  I  L  K  M  F  P  S  T  W  Y  V  B  Z  X  * ) ],
             [ map { shift @$_; $_ }
               (
                 #        A  R  N  D  C  Q  E  G  H  I  L  K  M  F  P  S  T  W  Y  V  B  Z  X  *   #
                 [ qw( A  4 -1 -2 -2  0 -1 -1  0 -2 -1 -1 -1 -1 -2 -1  1  0 -3 -2  0 -2 -1  0 -4 ) ],
                 [ qw( R -1  5  0 -2 -3  1  0 -2  0 -3 -2  2 -1 -3 -2 -1 -1 -3 -2 -3 -1  0 -1 -4 ) ],
                 [ qw( N -2  0  6  1 -3  0  0  0  1 -3 -3  0 -2 -3 -2  1  0 -4 -2 -3  3  0 -1 -4 ) ],
                 [ qw( D -2 -2  1  6 -3  0  2 -1 -1 -3 -4 -1 -3 -3 -1  0 -1 -4 -3 -3  4  1 -1 -4 ) ],
                 [ qw( C  0 -3 -3 -3  9 -3 -4 -3 -3 -1 -1 -3 -1 -2 -3 -1 -1 -2 -2 -1 -3 -3 -2 -4 ) ],
                 [ qw( Q -1  1  0  0 -3  5  2 -2  0 -3 -2  1  0 -3 -1  0 -1 -2 -1 -2  0  3 -1 -4 ) ],
                 [ qw( E -1  0  0  2 -4  2  5 -2  0 -3 -3  1 -2 -3 -1  0 -1 -3 -2 -2  1  4 -1 -4 ) ],
                 [ qw( G  0 -2  0 -1 -3 -2 -2  6 -2 -4 -4 -2 -3 -3 -2  0 -2 -2 -3 -3 -1 -2 -1 -4 ) ],
                 [ qw( H -2  0  1 -1 -3  0  0 -2  8 -3 -3 -1 -2 -1 -2 -1 -2 -2  2 -3  0  0 -1 -4 ) ],
                 [ qw( I -1 -3 -3 -3 -1 -3 -3 -4 -3  4  2 -3  1  0 -3 -2 -1 -3 -1  3 -3 -3 -1 -4 ) ],
                 [ qw( L -1 -2 -3 -4 -1 -2 -3 -4 -3  2  4 -2  2  0 -3 -2 -1 -2 -1  1 -4 -3 -1 -4 ) ],
                 [ qw( K -1  2  0 -1 -3  1  1 -2 -1 -3 -2  5 -1 -3 -1  0 -1 -3 -2 -2  0  1 -1 -4 ) ],
                 [ qw( M -1 -1 -2 -3 -1  0 -2 -3 -2  1  2 -1  5  0 -2 -1 -1 -1 -1  1 -3 -1 -1 -4 ) ],
                 [ qw( F -2 -3 -3 -3 -2 -3 -3 -3 -1  0  0 -3  0  6 -4 -2 -2  1  3 -1 -3 -3 -1 -4 ) ],
                 [ qw( P -1 -2 -2 -1 -3 -1 -1 -2 -2 -3 -3 -1 -2 -4  7 -1 -1 -4 -3 -2 -2 -1 -2 -4 ) ],
                 [ qw( S  1 -1  1  0 -1  0  0  0 -1 -2 -2  0 -1 -2 -1  4  1 -3 -2 -2  0  0  0 -4 ) ],
                 [ qw( T  0 -1  0 -1 -1 -1 -1 -2 -2 -1 -1 -1 -1 -2 -1  1  5 -2 -2  0 -1 -1  0 -4 ) ],
                 [ qw( W -3 -3 -4 -4 -2 -2 -3 -2 -2 -3 -2 -3 -1  1 -4 -3 -2 11  2 -3 -4 -3 -2 -4 ) ],
                 [ qw( Y -2 -2 -2 -3 -2 -1 -2 -3  2 -1 -1 -2 -1  3 -3 -2 -2  2  7 -1 -3 -2 -1 -4 ) ],
                 [ qw( V  0 -3 -3 -3 -1 -2 -2 -3 -3  3  1 -2  1 -1 -2 -2  0 -3 -1  4 -3 -2 -1 -4 ) ],
                 [ qw( B -2 -1  3  4 -3  0  1 -1  0 -3 -4  0 -3 -3 -2  0 -1 -4 -3 -3  4  1 -1 -4 ) ],
                 [ qw( Z -1  0  0  1 -3  3  4 -2  0 -3 -3  1 -1 -3 -1  0 -1 -3 -2 -2  1  4 -1 -4 ) ],
                 [ qw( X  0 -1 -1 -1 -2 -1 -1 -1 -1 -1 -1 -1 -1 -1 -2  0  0 -2 -1 -1 -1 -1 -1 -4 ) ],
                 [ qw( * -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4  1 ) ]
               )
             ]
           )
}

sub max { $_[0] > $_[1] ? $_[0] : $_[1] }

sub consensus_residues
{
    my ( $cnt_hash, $min_match, $conserve_hash ) = @_;

    #  Sort the residues from most to least frequent, and note first 2:

    my %cnt = %$cnt_hash;
    my ( $c1, $c2, @c );

    ( $c1, $c2 ) = @c = sort { $cnt{$b} <=> $cnt{$a} } keys %cnt;
    ( $cnt{$c1} >= 2 ) or return ( '', '' );

    #  Are there at least $min_match of the most abundant?

    if ( $cnt{$c1} >= $min_match )
    {
        $c2  = '';
    }

    #  Are there at least $min_match of the two most abundant?

    elsif ( ( $cnt{$c2} >= 2 ) && ( ( $cnt{$c1} + $cnt{$c2} ) >= $min_match ) )
    {
        $c1 = lc $c1;
        $c2 = lc $c2;
    }

    #  Can we make a consensus of conservative changes?

    else
    {
        $c2 = '';
        my ( $is_conservative, @pos );
        my $found = 0;
        foreach $c1 ( grep { /^[AC-IK-NP-TVWY]$/ } @c )
        {
            ( $is_conservative = $conserve_hash->{ $c1 } ) or next;
            @pos = grep { $is_conservative->{ $_ } } @c;
	    my @sumarr = map { $cnt{ $_ } } @pos;
	    my $total = 0;
	    foreach my $s ( @sumarr ) {
	      $total += $s;
	    }
#	      $total = sum( map { $cnt{ $_ } } @pos );
            if ( $total >= $min_match ) { $found = 1; last }
        }
        $c1 = $found ? lc $c1 : '';
    }

    return ( $c1, $c2, @c );
}

sub consensus_colors
{
    my ( $pallet, $conservative, $c1, $c2, @c ) = @_;
#   print STDERR Dumper( $c1, $c2, \@c ); exit;
    return {} if ! $c1;

    my %pallet = ( ref($pallet) eq 'HASH' ) ? %$pallet
                                            : @{ scalar consensus_pallet() };

    $conservative = {} if ref( $conservative ) ne 'HASH';

    #  Mark everything but ' ' and . as mismatch, then overwrite exceptions:

    my %color = map  { $_ => $pallet{ mismatch } }
                grep { ! /^[ .]$/ }
                @c;

    if ( $c1 ne '-' )
    {
        $c1 = uc $c1;
        foreach ( @{ $conservative->{$c1} || [] } )
        {
            $color{ $_ } = $pallet{ positive }
        }
        $color{ $c1 } = $pallet{ consen1 };
        if ( $c2 )
        {
            $color{ uc $c2 } = ( $c2 ne '-' ) ? $pallet{ consen2 } : $pallet{ consen2g };
        }
    }
    else
    {
        $color{ $c1 } = $pallet{ consen1g };
        if ( $c2 ) { $color{ uc $c2 } = $pallet{ consen2 } }
    }

    #  Copy colors to lowercase letters:

    foreach ( grep { /^[A-Z]$/ } keys %color )
    {
        $color{ lc $_ } = $color{ $_ }
    }

    return \%color;
}

sub html_esc
{
    my $txt = shift;
    $txt =~ s/\&/&amp;/g;
    $txt =~ s/\</&lt;/g;
    $txt =~ s/\>/&gt;/g;
    return $txt;
}


sub get_flanking {
  my ( $self, $fid, $before, $after ) = @_;

  if ( $before < $after ) {
    my $this = $before;
    $before = $after;
    $after = $this;
  }

  return if ( !defined( $fid ) || $fid !~ /^fig/ );

  my $feat_seq = $self->{ 'fig' }->get_dna_seq( $fid );
  my $length_feat = length( $feat_seq );

  my $feature_location = $self->{ 'fig' }->feature_location( $fid );
  my $genome = $self->{ 'fig' }->genome_of( $fid );
  my $additional = $self->{ 'cgi' }->param( 'FLANKING' ) || 500;

  my @loc = split /,/, $feature_location;
  my ( $contig, $beg, $end ) = BasicLocation::Parse( $loc[0] );

  if ( defined( $contig ) and defined( $beg ) and defined( $end ) ) {
    my ( $n1, $npre );
    if ( $beg < $end ) {
      $n1 = $beg - $before;
      $n1 = 1 if $n1 < 1;
      $npre = $beg - $n1;
    }
    else {
      $n1 = $beg + $before;
      my $clen = $self->{ 'fig' }->contig_ln( $genome, $contig );
      $n1 = $clen if $n1 > $clen;
      $npre = $n1 - $beg;
    }
    
    # Add to the end of the last segment:
    ( $contig, $beg, $end ) = BasicLocation::Parse($loc[-1]);
    my ( $n2, $npost );
    if ( $beg < $end ) {
      $n2 = $beg - $after;
      my $clen = $self->{ 'fig' }->contig_ln( $genome, $contig );
      $n2 = $clen if $n2 > $clen;
      $npost = $beg - $n2;
    } 
    else {
      $n2 = $beg + $after;
      $n2 = 1 if $n2 < 1;
      $npost = $n2 - $beg;
    }
    $loc[0] = join( '_', $contig, $n1, $n2 );
    
    my $seq = $self->{ 'fig' }->dna_seq( $genome, join( ',', @loc ) );
    if ( $seq ) {

      if ( $npost > 0 ) {
	$seq = lc( substr( $seq, 0 ) );
      }
      elsif ( $npre < 0 ) {
	$seq = uc( substr( $seq, 0 ) );
      }
      elsif ( $length_feat < abs( $npost ) ) {
	$seq = lc( substr( $seq, 0, $npre ) ) . uc( substr( $seq, $npre, $length_feat ) ) . lc( substr( $seq, ( $npre + $length_feat ) ) );
      }
      else {       
	$seq = lc( substr( $seq, 0, $npre ) ) . uc( substr( $seq, $npre ) );
      }
      return $seq;
    }
  }
}

sub viewAnnotations {
  my ( $self, $checked ) = @_;

  my @checked = $self->{ 'cgi' }->param( 'checked' );

  my $html;
  my $col_hdrs = ["who","when","annotation"];
  $html .= join("\n", "<table border=\"2\" align=\"center\">",
		$self->{ 'cgi' }->Tr($self->{ 'cgi' }->th({ align => "center" }, $col_hdrs)),
		"");
  foreach my $cb ( @checked ) {
    if ( $cb =~ /^checked_(fig.*)/ ) {
      my $fid = $1;
      my $tab = [ map { [$_->[2],$_->[1],$_->[3]] } $self->{ 'fig' }->feature_annotations($fid) ];
      my $title = (@$tab == 0 ? "No " : "") . "Annotations for $fid";
      $html .= join("\n", $self->{ 'cgi' }->Tr( $self->{ 'cgi' }->td({ colspan => 3, align => "center" }, $title ) ), "");
      if ( @$tab > 0 ) {
	for my $row ( @$tab ) {
	  $html .= $self->{ 'cgi' }->Tr( $self->{ 'cgi' }->td( $row ) );
	}
      }
    }
  }
  $html .= "</table>\n";
  return $html;
}

sub annotateTree {
  my ( $self ) = @_;
  
  my $html = '';
  my $from = $self->{ 'cgi' }->param( 'from' );
  my @checked = $self->{ 'cgi' }->param( 'checked' );
  
  if ( defined( $from ) && ( my $func = $self->{ 'fig' }->function_of( $from, $self->{ 'seeduser' } ) ) ) {
    $func =~ s/\s+\#[^\#].*$//;
    foreach my $cb ( @checked ) {
      if ( $cb =~ /^checked_(fig.*)/ ) {
 	my $peg = $1;
	
 	if ( $self->{ 'fig' }->assign_function( $peg, $self->{ 'seeduser' }, $func, "" ) ) {
 	  $html .= $self->{ 'cgi' }->h3( "Done for $peg" );
 	}
 	else {
	  $html .= $self->{ 'cgi' }->h3( "Failed for $peg" );
 	}
      }
    }
  }
  else {
    $html .= join("\n", "<table border=1>",
 		  "<tr><td>Protein</td><td>Organism</td><td>Current Function</td><td>By Whom</td></tr>",
 		  "");
    my $defaultann = ''; # this will just be the last function with BUT NOT added if we are negating the function
    foreach my $peg ( @checked ) {
      my @funcs = $self->{ 'fig' }->function_of( $peg );
      if ( ! @funcs ) { 
	@funcs = ( [ "", ] ) 
      }
      my $nfunc = @funcs;
      my $org = $self->{ 'fig' }->org_of( $peg );
      $html .= join("\n", "<tr>",
 		    "<td rowspan=$nfunc>$peg</td>",
 		    "<td rowspan=$nfunc>$org</td>",
 		    ""
 		   );
      my ( $who, $what );
      $html .=  join( "</tr>\n<tr>", map { ($who,$what) = @$_; "<td>$what</td><td>$who</td>" } @funcs );
      $html .= "</tr>\n";
      if ( $self->{ 'cgi' }->param( "negate" ) ) {
 	$defaultann = "$what BUT NOT";
      }
    }
    $html .= "</table>\n";
  }
  return $html;
}


###########################
# Buttons under the table #
###########################
sub get_actions {

  my ( $self, $seqs ) = @_;
  my $application = $self->application;

#  my $buttons = "<DIV id='controlpanel' style='width: 80%;'>
  my $buttons = "<H1>Options</H1>\n";
  $buttons .= "<P>Here you can choose what type of sequence you want to see, if you would like to see an alignment and what format it should have, as well as if and what format of a tree you would like to see.</P>";

  foreach my $s ( @$seqs ) {
    $buttons .= $self->{ 'cgi' }->hidden( -name => 'fid', -value => $s ),
  }

  my $reload    = "<INPUT TYPE=BUTTON name='Reload' value='Reload' onclick='submitPage( \"Reload\" )'>\n";
  my $before = 0;
  my $after = 0;

  my $checked_dnaseq = '';
  my $checked_dnaflank = '';
  my $checked_proteinseq = '';
  if ( $self->{ 'seq_format' } eq 'DNA' ) {
    $checked_dnaseq = 'CHECKED';
  }
  elsif ( $self->{ 'seq_format' } =~ /^pre_(-?\d+)_(-?\d+)/ ) {
    $checked_dnaflank = 'CHECKED';
    $before = $1;
    $after = $2;
  }
  else {
    $checked_proteinseq = 'CHECKED';
  }

  my $checked_fastaal = '';
  my $checked_clustalal = '';
  my $checked_specialal = '';
  my $checked_noal = '';
  if ( $self->{ 'align_format' } eq 'fasta' ) {
    $checked_fastaal = 'CHECKED';
  }
  elsif ( $self->{ 'align_format' } eq 'special' ) {
    $checked_specialal = 'CHECKED';
  }
  elsif ( $self->{ 'align_format' } eq 'clustal' ) {
    $checked_clustalal = 'CHECKED';
  }
  else {
    $checked_noal = 'CHECKED';
  }

  my $checked_newick = '';
  my $checked_normal = '';
  my $checked_notree = '';
  if ( defined( $self->{ 'tree_format' } ) && $self->{ 'tree_format' } eq 'newick' ) {
    $checked_newick = 'CHECKED';
  }
  elsif ( defined( $self->{ 'tree_format' } ) && $self->{ 'tree_format' } eq 'normal' ) {
    $checked_normal = 'CHECKED';
  }
  else {
    $checked_notree = 'CHECKED';
  }

  my $firstpoint = "<INPUT TYPE=TEXT NAME='firstpoint' ID='firstpoint' SIZE=10 VALUE='$before'>";
  my $secondpoint = "<INPUT TYPE=TEXT NAME='secondpoint' ID='secondpoint' SIZE=10 VALUE='$after'>";

  my $proteinbox = "<INPUT TYPE=\"RADIO\" NAME=\"Sequence\" VALUE=\"protein\" ID=\"PROTEIN\" $checked_proteinseq >";
  my $dnabox = "<INPUT TYPE=\"RADIO\" NAME=\"Sequence\" VALUE=\"DNA\" ID=\"DNASEQ\" $checked_dnaseq >";
  my $flankingbox = "<INPUT TYPE=\"RADIO\" NAME=\"Sequence\" VALUE=\"pre\" ID=\"DNAFLANK\" $checked_dnaflank >";

  my $fastabox   = "<INPUT TYPE=\"RADIO\" NAME=\"Alignment\" VALUE=\"fasta\" ID=\"FASTAAL\" $checked_fastaal >";
  my $clustalbox = "<INPUT TYPE=\"RADIO\" NAME=\"Alignment\" VALUE=\"clustal\" ID=\"CLUSTALAL\" $checked_clustalal >";
  my $specialbox = "<INPUT TYPE=\"RADIO\" NAME=\"Alignment\" VALUE=\"special\" ID=\"SPECIALAL\" $checked_specialal >";
  my $noalbox = "<INPUT TYPE=\"RADIO\" NAME=\"Alignment\" VALUE=\"noal\" ID=\"NOAL\" $checked_noal >";

  my $newickbox = "<INPUT TYPE=\"RADIO\" NAME=\"Tree\" VALUE=\"newick\" ID=\"NEWICKTREE\" $checked_newick >";
  my $normalbox = "<INPUT TYPE=\"RADIO\" NAME=\"Tree\" VALUE=\"normal\" ID=\"NORMALTREE\" $checked_normal >";
  my $notreebox = "<INPUT TYPE=\"RADIO\" NAME=\"Tree\" VALUE=\"notree\" ID=\"NOTREE\" $checked_notree >";

  $buttons .= "<TABLE><TR><TD><B>Sequence:</B></TD><TD>$proteinbox Protein</TD><TD>$dnabox DNA</TD><TD COLSPAN=2>$flankingbox upstream DNA: $firstpoint - $secondpoint</TD></TR>";
  $buttons .= "<TR><TD><B>Alignment:</B></TD><TD>$noalbox No Alignment</TD><TD>$fastabox Fasta:</TD><TD>$clustalbox Clustal</TD><TD>$specialbox Special</TD></TR>";
  $buttons .= "<TR><TD><B>Tree:</B></TD><TD>$notreebox No Tree</TD><TD>$newickbox Newick</TD><TD>$normalbox NJTree</TD></TR></TABLE><BR>";
  $buttons .= "<TABLE><TR><TD>$reload</TD></TR></TABLE>";
#  $buttons .= "</DIV>";

  return $buttons;
}
