package WebPage::TermsofService;

use base qw( WebPage );

use strict;
use warnings;

use Conf;

1;

sub init {
  my ($self) = @_;

  $self->title('Terms of Service');
  $self->application->register_action($self, 'check_terms', 'check_terms');
  $self->omit_from_session(1);

  return 1;
}

sub output {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();
  my $user = $application->session->user();
    
  my $version = $Conf::require_terms_of_service;
  
  my $html = "";

  if ($version == 1) {
    
    $html .= "<center>";    
    $html .= "<h1>Terms of Service</h1>";
    $html .= "<h3>for RAST and MG-RAST</h3>";
    $html .= $self->start_form( 'check_terms_form', { action => 'check_terms' } ); 
    $html .= "<br><div style='text-align:left; width: 400px;'>";
    $html .= "<p>Dear ".$user->firstname()." ".$user->lastname().",</p>";
    $html .= "<p>We are asking that users specify their funding source and agree to the following terms of service. This information will only be used for... Add more soothing text here so users will not freak out.</p><br>";
    $html .= "<p><b>1. Please specify your project's funding source:</b></p>";
    $html .= "<p>Select all that are applicable.</p>";
    $html .= "<input type='checkbox' name='nih'>NIH<br>";
    $html .= "<input type='checkbox' name='doe'>DOE<br><br>";
    $html .= "<input type='checkbox' name='other'>Other<br>";
    $html .= "If you have selected other please specify<br><input type='text' name='other_value'><br><br><br>";
    
    $html .= "<p><b>2. Please read the below terms of service:</b></p>";
    $html .= "<input type='submit' name='iagree' value='I agree to the terms of service'/>";
    $html .= "<p>If you feel you are unable to agree to the terms above please navigate away from this page.</p>";
    $html .= "</div>";
    $html .= $self->end_form();
    $html .= "</center>";

  } elsif ($version == 2) {

    $html .= "<center>";    
    $html .= "<h1>Terms of Service</h1>";
    $html .= "<h3>for MG-RAST</h3>";
    $html .= $self->start_form( 'check_terms_form', { action => 'check_terms' } ); 
    $html .= "<br><div style='text-align:left; width: 800px;'>";
    $html .= "<p>Dear ".$user->firstname()." ".$user->lastname().",</p>";
    $html .= "<p><b>1. Please specify your project's funding source:</b></p>";
    $html .= "<p>Select all that are applicable.</p>";
    $html .= "<input type='checkbox' name='doe'>DOE<br>";
    $html .= "<input type='checkbox' name='nih'>NIH<br>";
    $html .= "<input type='checkbox' name='usda'>USDA<br>";
    $html .= "<input type='checkbox' name='nsf'>NSF<br>";
    $html .= "<input type='checkbox' name='eu'>EU (any funding agency in the EU)<br><br>";
    $html .= "<input type='checkbox' name='other'>other<br>";
    $html .= "If you have selected other please specify<br><input type='text' name='other_value'><br><br><br>";
    
    $html .= "<p><b>2. Please read the below terms of service:</b></p>";
    $html .= "<p>1. MG-RAST is a web-based computational metagenome analysis service provided on a best-effort basis. We strive to provide correct analysis, privacy, but can not guarantee correctness of results, integrity of data or privacy. That being said, we are not responsible for any HIPPA regulations regarding human samples uploaded by users. We will try to provide as much speed as possible and will try to inform users about wait times. We will inform users about changes to the system and the underlying data.<br>2. We reserve the right to delete non public data sets after 120 days.<br>3. We reserve the right to reject data set that are not complying with the purpose of MG-RAST.<br>4. We reserve the right to perform additional data analysis (e.g. search for novel sequence errors to improve our sequence quality detection, clustering to improve sequence similarity searches etc.) AND in certain cases utilize the results. We will NOT release user provided data without consent and or publish on user data before the user.<br>5. User acknowledges the restrictions stated about and will cite MG-RAST when reporting on their work.<br>6. User acknowledges the fact that data sharing on MG-RAST is meant as a pre-publication mechanism and we strongly encourage users to make data publicly accessible in MG-RAST once published in a journal (or after 120 days).<br>7. User acknowledges that data (including metadata) provided is a) correct and b) user has either own the data or has the permission of the owner to upload data and or publish data on MG-RAST.<br>8. We reserve the right to curate and update public meta data.<br>9. We reserves the right at any time to modify this Agreement. Such modifications and additional terms and conditions will be effective immediately and incorporated into this Agreement. MG-RAST will make a reasonable effort to contact users via email of any changes and your continued use of MG-RAST will be deemed acceptance thereof.</p>";
    $html .= "<input type='submit' name='iagree' value='I agree to the terms of service'/>";
    $html .= "<p>If you feel you are unable to agree to the terms above please navigate away from this page.</p>";
    $html .= "</div>";
    $html .= $self->end_form();
    $html .= "</center>";

  }

  return $html;
}

sub check_terms {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  
  my $master = $application->dbmaster;
  my $user = $application->session->user;

  if ($user && $master && $cgi->param('iagree')) {
    my $pref = $master->Preferences->get_objects( { user => $user,
						    name => 'AgreeTermsOfService' } );
    if (scalar(@$pref) && $pref->[0]->value >= $Conf::require_terms_of_service) {
      $application->add_message('info', "You had already agreed to the terms of service.");
    } else {
      if (scalar(@$pref)) {
	$pref->[0]->value($Conf::require_terms_of_service);
      } else {
	$pref = $master->Preferences->create( { user => $user,
						name => 'AgreeTermsOfService',
						value => $Conf::require_terms_of_service } );
	if ($pref) {
	  if ($cgi->param('nih')) {
	    $master->Preferences->create( { user => $user,
					    name => 'funding_source',
					    value => 'nih' } );
	  }
	  if ($cgi->param('doe')) {
	    $master->Preferences->create( { user => $user,
					    name => 'funding_source',
					    value => 'doe' } );
	  }
	  if ($cgi->param('usda')) {
	    $master->Preferences->create( { user => $user,
					    name => 'funding_source',
					    value => 'usda' } );
	  }
	  if ($cgi->param('nsf')) {
	    $master->Preferences->create( { user => $user,
					    name => 'funding_source',
					    value => 'nsf' } );
	  }
	  if ($cgi->param('eu')) {
	    $master->Preferences->create( { user => $user,
					    name => 'funding_source',
					    value => 'eu' } );
	  }
	  if ($cgi->param('other_value')) {
	    $master->Preferences->create( { user => $user,
					    name => 'funding_source',
					    value => $cgi->param('other_value') } );
	  }
	} else {
	  $application->add_message('warning', "unable to create user preference for terms of service");
	}
      }
    }
  }
  
  $application->redirect($application->default);
  
  return 1;
}
