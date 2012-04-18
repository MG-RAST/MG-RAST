#!/usr/bin/env perl

BEGIN {
    unshift @INC, qw(
              /Users/jared/gitprojects/MG-RAST/site/lib
              /Users/jared/gitprojects/MG-RAST/site/lib/WebApplication
              /Users/jared/gitprojects/MG-RAST/site/lib/PPO
              /Users/jared/gitprojects/MG-RAST/site/lib/MGRAST
              /Users/jared/gitprojects/MG-RAST/conf
	);
}
use Data::Dumper;
use FIG_Config;
# end of tool_hdr
########################################################################
package AnnotationClearingHouse::WebPage::UploadAnnotation;

# $Id: UploadAnnotation.cgi,v 1.1 2009-12-01 15:22:43 wilke Exp $

use strict;
use warnings;

use base qw( WebPage );

use AnnoClearinghouse;
use FIG_Config;

1;


sub init {
  my $self = shift;

  $self->title("Annotation Clearing House - Upload Annotation");
  $self->application->register_action($self, 'upload_annotation', 'upload_annotation');

  my $dbh  = $self->application->data_handle('ACH');
  my $anno = new AnnoClearinghouse($FIG_Config::clearinghouse_data,
				   $FIG_Config::clearinghouse_contrib,
				   0,
				   $dbh);
  $self->data('aclh', $anno);
  $self->data('bad_list', []);

}


sub output {
  my ($self) = @_;

  my $content = "<h1>Upload new annotation</h1>";
  $content .= "<p>To upload your manual annotations to the annotation clearing house, please submit a file in plain text format with tab separated entries of identifier and annotation (one per line). If you upload more annotations at a later time, those annotations will be added to your current set. Duplicate entries will be merged so that later annotations overwrite any previous ones.</p>"; 

  $content .= $self->start_form('upload_form', { 'page' => 'UploadAnnotation',
					         'action' => 'upload_annotation' 
					       });
  $content .= "<table><tr><th>Select an annotation file: </th>";
  $content .= "<td><input name='file' type='file' maxlength='200000' accept='text/*'>";
  $content .= "<input type='submit' value=' Submit '>";
  $content .= "</td></tr></table";
  $content .= $self->end_form();


  # check any bad annotations from an upload
  if (scalar(@{$self->data('bad_list')})) {
    $content .= "<h2>Your last upload contained the following problems:</h2>";
    $content .= "<table style='margin-bottom: 10px;'>";
    $content .= "<tr><th class='result'>Line</th><th class='result'>Identifier</th><th class='result'>Problem</th></tr>";
    my $odd=1;
    foreach (@{$self->data('bad_list')}) {
      my ($id, $line, $problem) = @$_;
      $id = '' unless ($id);
      my $css_class = ($odd) ? 'odd' : 'even';
      $odd = ($odd) ? 0 : 1;
      $content .= "<tr><td class='$css_class'>$line</td>".
	"<td width='400px' class='$css_class'>$id</td>".
	"<td width='150px' class='$css_class'>$problem</td></tr>";
    }
    $content .= "</table>";
  }


  return $content;
}


sub upload_annotation {
  my ($self) = @_;
  
  my $file = $self->application->cgi->upload('file');
  my $result = 0;
  my $login = $self->application->session->user->login;

  eval { 
    $result = $self->data('aclh')->import_user_annotations($login, $file, $self->data('bad_list'));
  };

  my $problems = (scalar(@{$self->data('bad_list')})) 
    ? 'There have been problems, please refer to the list at the bottom for details.' 
    : '';

  if ($@) {
    my $error = $@;
    $error =~ s/ at [\w\/\\]+AnnoClearinghouse.pm line \d+\.$//;
    $self->application->add_message('warning', "Your upload has produced an error: <br/><pre>$error</pre>");
  }
  else {
    $self->application->add_message('info', "You successfully added $result annotations. $problems");
  }

  return 1;
}


sub required_rights {
  return [ [ 'login' ],
	 ];
}
