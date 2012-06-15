package AnnotationClearingHouse::WebPage::Evaluate;

# $Id: Evaluate.pm,v 1.1 2009-12-01 15:22:43 wilke Exp $

use strict;
use warnings;

use base qw( WebPage );

use AnnoClearinghouse;
use Config;
use FIG;
use DBMaster;

1;


sub init {
  my $self = shift;
  $self->title("Annotation Clearing House - Evaluate");

}


sub output {
    my ($self) = @_;
    
    my $anno = new AnnoClearinghouse($Config::clearinghouse_data,
				     $Config::clearinghouse_contrib);
    
    my $category = $self->application->cgi->param('category') || 'identifier';
    my $query = $self->application->cgi->param('query') || '';
    
    # ignore leading/trailing spaces
    $query =~ s/^\s+//;
    $query =~ s/\s+$//;
    
    # get principal ids (blocks)
    my %ids;
    if ($category eq 'identifier') {
	$query =~ s/,/, /g;
	my @query = split(', ',$query);
	foreach my $q (@query) {
	    my $pid = $anno->lookup_principal_id($q);
	    $ids{$pid}++ if ($pid);
	}
    }
    else {
	die "Unknown search category in __PACKAGE__";
    }
    
    # start a hash with user login to user full name mappings
    my $users = { };
    my ($query_func, $query_source);
    my $func_line = "";
    if ($category eq 'identifier'){
	($query_func, $query_source) = $anno->get_assignment($query);
    }

    # generate html table output and raw dump tsv
    my $html = "<div id='query_info'>";
    $html .= "</div>";
    $html .= "<p><strong>You are evaluating for $category with the following query: $query</strong></p>";
    
    $html .= $self->start_form("evaluation_form");
    $self->application->register_component('Ajax', 'evaluate_sources');
    $html .= $self->application->component('evaluate_sources')->output();
	
    if (scalar(keys %ids)) {
	for my $id (keys %ids) {
      
	    # get, merge and sort the data
	    my @r = $anno->get_annotations_by_pid($id);
	    my @c = $anno->get_user_annotations_by_pid($id);
	    push @r, @c;
	    @r = sort { $a->[0] cmp $b->[0] } @r;
	    
	    # start the table
	    my $odd=1;
	    $html .= "<table style='margin-bottom: 10px;'>";
	    my ($query_genome) = ($query) =~ /^fig\|(\d+?\.\d?)\./;
	    
	    my $user = $self->application->session->user;
	    $html .= 	  "<th class='result'>Assignment</th><th class='result'>Does the assignment accurately describe the query sequence?</th></tr>";
	    
	    my $current_org = '';
	    my $current_len = '';
	    my $n = 0;
	    my $annotations = {};

	    foreach my $e (@r) {
		my ($id, $source, $func, $org, $len) = @$e;
		
		# is it a contributed annotation?
                my $contrib = (scalar(@$e) == 3) ? 1 : 0;
		
		# translate users for contribs
                my $source_string = $source;
                if ($contrib) {
                    unless (exists $users->{$source}) {
                        my $func_user = $self->application->dbmaster->User->init({ login => $source });
                        unless (ref $func_user) {
                            warn "Unknown user for annotation: $id, $source, $func.";
                            next;
                        }
                        $users->{ $func_user->login } = $func_user->firstname.' '.$func_user->lastname;
                    }
                    $source_string = $users->{$source};
		}
		push (@{$annotations->{$func}}, "$id~$source_string");
	    }

	    my $seen_function = {};
	    foreach my $e (@r) {	
		my ($id, $source, $func, $org, $len) = @$e;
		next if ($seen_function->{$func});
		$seen_function->{$func}++;
		
		# generate table
		my $css_class = ($odd) ? 'odd' : 'even';
		$odd = ($odd) ? 0 : 1;
		
		$html .= "<tr><td width='400px' class='$css_class'>$func</td>".
		    "<td width='200px' class='$css_class'><input type='radio' id='radio_" . $n . "' name='radio_" . $n . "' value='Yes'>Yes".
		    "<input type='radio'  id='radio_" . $n . "' name='radio_" . $n . "' value='No'>No<input type='radio'  id='radio_" . $n . "' name='radio_" . $n . "' value='Skip'>Skip".
		    "<input type='hidden' id='hidden_" . $n . "' value='" . join("%", @{$annotations->{$func}}) . "'></td></tr>";
		
		$n++;
	    }
	    $html .= "</table>";
	    $html .= "<input type='hidden' id='evaluation_qty' name='evaluation_qty' value='" . $n . "'>";
	}

    }
    else {
	$html .= "<p><em>No results found.</em></p>";
    }
    $html .= qq~<input type='button' name='evaluate' id='evaluate' onClick="execute_ajax('add_evaluation', 'query_info', 'evaluation_form', 'Processing...', 0);" value='Submit'>~;
    $html .= $self->end_form;

    # generate page content
    my $content = "<h1>Evaluate the Annotation Clearing House</h1>\n";
    
    $content .= $html;
    return $content;
    
}


# former link to uniprot/swissprot
# "<a href='http://ca.expasy.org/uniprot/$copy'>$id</a>";

sub add_evaluation {
    my ($self) = @_;
    
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $content;
    
    # load the db
    my $dbmaster = DBMaster->new(-database => '/home/arodri7/public_html/FIGdisk/dist/releases/dev/EvaluateAnnotation/EvaluateAnnotation.db -backend => 'SQLite', user => 'root');
#    my $dbmaster = DBMaster->new(-database => 'EvaluateAnnotation', -backend => 'SQLite', user => 'root');

    my $query = $cgi->param('query');
    my $evaluate_qty = $cgi->param('evaluate_qty');

    for (my $i=0;$i<$evaluate_qty;$i++){
	my $value = $cgi->param('radio_' . $i);
	my $id_dbs = $cgi->param('hidden_' .$i);
	print STDERR "VALUE: $value, IDS: $id_dbs\n";
    }
    return $content;
}

sub get_url_for_id {
  my ($self, $id) = @_;

  my $copy = $id;
  if ($copy =~ s/^kegg\|//) {
    return "<a href='http://www.genome.jp/dbget-bin/www_bget?$copy'>$id</a>";
  }
  elsif ($copy =~ s/^sp\|//) {
    return "<a href='http://www.uniprot.org/entry/$copy'>$id</a>";
  }
  elsif ($copy =~ s/^tr\|//) {
    return "<a href='http://www.uniprot.org/entry/$copy'>$id</a>";
  }
  elsif ($copy =~ s/^uni\|//) {
    return "<a href='http://www.uniprot.org/entry/$copy'>$id</a>";
  }
  elsif ($copy =~ s/^gi\|//) {
    return "<a href='http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=protein&id=$copy'>$id</a>";
  }
  elsif ($copy =~ s/^ref\|//) {
    return "<a href='http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=protein&id=$copy'>$id</a>";
  }
  elsif ($copy =~ s/^gb\|//) {
    return "<a href='http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=protein&id=$copy'>$id</a>";
  }
  elsif ($copy =~ s/^cmr\|// or $copy =~ s/^tigrcmr\|//) {
    return "<a href='http://cmr.tigr.org/tigr-scripts/CMR/shared/GenePage.cgi?locus=$copy'>$id</a>";
  }
  elsif ($copy =~ /^fig\|/) {
    return "<a href='http://seed-viewer.theseed.org/linkin.cgi?id=$id'>$id</a>";
  }
  elsif ($copy =~ s/^img\|//) {
    return "<a href='http://img.jgi.doe.gov/cgi-bin/pub/main.cgi?section=GeneDetail&page=geneDetail&gene_oid=$copy'>$id</a>";
  }
  else {
    return $id;
  }

}

sub changeAssignment{
    my ($self) = @_;
    my $content;

    my $fig = $self->application->data_handle('FIG');
    my $cgi = $self->application->cgi();

    my $new_function = $cgi->param('new_function');
    my $query = $cgi->param('query');

    my $user = $self->application->session->user;
    
    # check if we have a valid fig
    unless ($fig) {
        $self->application->add_message('warning', 'Invalid organism id');
        return "";
    }

    my ($infos, $warnings);
    if ($user && $user->has_right(undef, 'annotate', 'genome', $fig->genome_of($query))) {
	print STDERR "function change would be here for $query to $new_function\n";
	#$fig->assign_function($query,$user->login,$new_function,"");
	#$fig->add_annotation($query,$user->login,"Set master function to\n$new_function\n.");
	$infos .= qq~<p class="info"><strong> Info: </strong>The function for ~ . $query . qq~ was changed to ~ . $new_function . qq~.~;
	$infos .= qq~<img onload="fade('info', 10);" src="./Html/clear.gif"/></p>~;

	$content .= qq~<div id="info"><p class="info">~ . $infos . qq~</div>~;
    }
    else{
	$warnings .= qq~<p class="warning"><strong> Warning: </strong>Unable to change annotation. You have no rights for editing sequence~ . $query . qq~.~;
	$warnings .= qq~<img onload="fade('warning', 10);" src="./Html/clear.gif"/></p>~;
	$content .= qq~<div id="warning"><p class="warning"><strong> Warning: </strong>~ . $warnings . qq~</div>~;
    }

    return $content;
}



sub required_rights {
  return [ [ 'login' ],
	   ];
}

