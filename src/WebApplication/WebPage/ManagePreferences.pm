package WebPage::ManagePreferences;

use strict;
use warnings;

use base qw( WebPage );

use Data::Dumper;

1;

=pod

#TITLE ManagePreferencesPagePm

=head1 NAME

ManagePreferences - an instance of WebPage which handles general preferences for users

=head1 DESCRIPTION

Display the set of preferences for a user and allow manipulation thereof

=head1 METHODS

=over 4

=item * B<init> ()

Initialize the page

=cut

sub init {
  my $self = shift;
  
  $self->title('Manage Preferences');
  $self->application->register_action($self, 'update_preferences', 'update_preferences');
  $self->{prefs} = $self->application->dbmaster->Preferences->get_objects( { user => $self->app->session->user() } );
  $self->application->register_component('Ajax', 'prefs_ajax');

}

=pod

=item * B<output> ()

Returns the html output of the PrivateOrganismPreferences page.

=cut

sub output {
  my ($self) = @_;

  # check user status
  my $user = $self->application->session->user();
  my $master = $self->application->dbmaster;
  my $user_status = 'normal';
  unless ($self->application->backend->name ne 'MGRAST' || $self->application->backend->name ne 'RNASEQRAST') {
    eval "use SeedViewer::SeedViewer";
    if ($user && user_can_annotate_genome($self->application, "*")) {
      $user_status = 'annotator';
    }
  }

  # get the data structures to display
  my $editable_preferences = $self->editable_preferences;
  my %categories;
  
  foreach my $key (keys(%$editable_preferences)) {
      if ($user && (my $what_admin = $editable_preferences->{$key}->{admin_only}))
      {
	  my $is = $user->is_admin($what_admin);
	  next if !$is;
      }
    # check if the current user should see this preference
    if (exists($editable_preferences->{$key}->{visibility})) {
      next unless ($user_status eq $editable_preferences->{$key}->{visibility});
      
    }

    # fill the category lists
    if (exists($categories{$editable_preferences->{$key}->{category}})) {
      push(@{$categories{$editable_preferences->{$key}->{category}}}, $key);
    } else {
      $categories{$editable_preferences->{$key}->{category}} = [ $key ];
    }
  }

  # get the current preferences
  my $prefs = $self->{prefs};
  foreach my $pref (@$prefs) {
    if (exists $editable_preferences->{$pref->name}) {
      if ($editable_preferences->{$pref->{name}}->{type} eq 'multiple') {
	if (ref($editable_preferences->{$pref->name}->{value}) ne 'ARRAY') {
	  $editable_preferences->{$pref->name}->{value} = [];
	}
	push(@{$editable_preferences->{$pref->name}->{value}}, $pref->value);
      } else {
	$editable_preferences->{$pref->name}->{value} = $pref->value;
      }
    }
  }

  # initialize content
  my $content = "<h1>Manage Preferences</h1><p style='width: 800px;'>Your preferences are divided into categories, which generally represent pages. If you have not yet chosen a preference for a certain setting, the default value will be used. You can come to this page and change your preferences at any time.</p>";

  # go through the categories
  foreach my $cat (sort(keys(%categories))) {
    $content .= $self->start_form('category_form', { action => 'update_preferences', category => $cat });
    $content .= "<h2>$cat</h2>";
    $content .= "<table>";
    foreach my $p (@{$categories{$cat}}) {
      next if ($editable_preferences->{$p}->{type} eq 'dependant');
      $content .= "<tr><th>".$editable_preferences->{$p}->{description}."</th><td>";
      if ($editable_preferences->{$p}->{type} eq 'list') {
	$content .= "<select name='$p'>";
	foreach my $entry (@{$editable_preferences->{$p}->{entries}}) {
	  my $selected = '';
	  if ($editable_preferences->{$p}->{value} eq $entry) {
	    $selected = ' selected=selected';
	  }
	  $content .= "<option value='$entry'$selected>$entry</option>";
	}
	$content .= "</select>";
      } elsif ($editable_preferences->{$p}->{type} eq 'generator') {
	$content .= "<div id='pref_div_$p'><input id='pref_val_$p' type='text' readOnly=1 name='$p' size=25 value='" . $editable_preferences->{$p}->{value} . "'></div><input type='button' value='generate new key' onclick='execute_ajax(\"". $editable_preferences->{$p}->{generator} ."\", \"pref_div_$p\", \"name=$p&key=\" + document.getElementById(\"pref_val_$p\").value);'>";
      } elsif ($editable_preferences->{$p}->{type} eq 'generator2') {
	my $tdate_readable = "";
	if ($editable_preferences->{WebServiceKeyTdate} && $editable_preferences->{WebServiceKeyTdate}->{value}) {
	  my $tdate = $editable_preferences->{WebServiceKeyTdate}->{value};
	  my ($sec,$min,$hour,$mday,$mon,$year) = localtime($tdate);
	  $tdate_readable = ($year + 1900)." ".sprintf("%02d", $mon + 1)."-".sprintf("%02d", $mday)." ".sprintf("%02d", $hour).":".sprintf("%02d", $min).".".sprintf("%02d", $sec);
	}
	$content .= "<div id='pref_div_$p'><input id='pref_val_$p' type='text' readOnly=1 name='$p' size=25 value='" . $editable_preferences->{$p}->{value} . "'><br><br><b>webkey termination date</b> <input type='text' readOnly=1 name='WebServiceKeyTdate' size=20 value='" . $tdate_readable . "'></div><input type='button' value='generate new key' onclick='execute_ajax(\"". $editable_preferences->{$p}->{generator} ."\", \"pref_div_$p\", \"name=$p&key=\" + document.getElementById(\"pref_val_$p\").value);'>";
      } elsif ($editable_preferences->{$p}->{type} eq 'generator3') {
	my $prefs = $master->Preferences->get_objects( { user => $user, name => 'oauth' } );
	$content .= "<select multiple=multiple>";
	foreach my $pref (@$prefs) {
	  $content .= "<option>".$pref->{value}."</option>";
	}
	$content .= "</select>&nbsp;&nbsp;&nbsp;";
	$content .= "<input type='button' value='add google identity' onclick='window.top.location=\"test.cgi\";'";
      } elsif ($editable_preferences->{$p}->{type} eq 'multiple') {
	unless (ref($editable_preferences->{$p}->{value}) eq 'ARRAY') {
	  $editable_preferences->{$p}->{value} = [];
	}
	$content .= "<textarea name='$p' rows=4 columns=40>".join("\n", @{$editable_preferences->{$p}->{value}})."</textarea>";
      } else {
	$content .= "<input type='text' name='$p' value='" . $editable_preferences->{$p}->{value} . "'>";
      }

      $content .= "</td>";
      
      # check for additional information
      if (exists($editable_preferences->{$p}->{info})) {
	$content .= "<td style='padding-left: 10px;'><i>".$editable_preferences->{$p}->{info}."</i></td>";
      }
    }
    $content .= "</table><br><input type='submit' value='set preferences'>";
    $content .= $self->end_form();
  }

  my $ajax = $self->application->component('prefs_ajax');
  $content .= $ajax->output();

  # return content
  return $content;
}

sub update_preferences {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $user = $self->application->session->user();

  my %prefs = map { $_->name => $_ } @{$self->{prefs}};
  my @params = $cgi->param;
  foreach my $param (@params) {
    if (exists($self->editable_preferences->{$param})) {
      if ($self->editable_preferences->{$param}->{type} eq 'multiple') {
	foreach my $p (@{$self->{prefs}}) {
	  if ($p->{name} eq $param) {
	    $p->delete;
	  }
	}
	foreach my $entry (split(/\r\n/, $cgi->param($param))) {
	  $application->dbmaster->Preferences->create( { user => $user,
							 name => $param,
							 value => $entry } );
	}
      } else {
	if (exists($prefs{$param})) {
          unless($param eq 'WebServiceKeyTdate' && $cgi->param($param) !~ /^\d+$/) {
	    $prefs{$param}->value($cgi->param($param));
          }
	} else {
	  $application->dbmaster->Preferences->create( { user => $user,
							 name => $param,
							 value => $cgi->param($param) } );
	}
      }
    }
  }
  $self->{prefs} = $self->application->dbmaster->Preferences->get_objects( { user => $self->app->session->user() } )
}

sub editable_preferences {
  my ($self) = @_;

  if ($self->application->backend->name eq 'MGRAST' || $self->application->backend->name eq 'RNASEQRAST') {
    return {
	    "funding_source" => { value => 'not selected',
				  description => 'funding sources',
				  type => 'multiple',
				  category => 'Funding' },
	    "confirm_proceed_non_ff_browser" => { value => 0,
						  description => 'do not display incorrect browser popup',
						  type => 'number',
						  category => 'Browser' },
	    "WebServicesKey" => { value => "",
				  description => "authentication key for web services",
				  type => 'generator2',
				  generator => "web_services_key_generator",
				  category => "Web Services",
				  info => "<b>Note:</b> Creating a new key and clicking 'set preferences'<br>will render the previous key deprecated. Your key will be valid for a limited time only (see webkey termination date). You can generate a new key with a new termination date at any time." },
	    "WebServiceKeyTdate" => { value => '',
				      type => 'dependant',
				      category => 'Web Services' }
	   #  "oauth" => { value => "",
	   # 		 description => "OAuth identities",
	   # 		 category => "Identity Management",
	   # 		 type => "generator3",
	   # 		 info => 'You can add accounts from google here, allowing you to log in with them.' },
	   };
  }

  return { "ComparedRegionsDefaultNumRegions" => { value => 4,
						   description => "default number of regions",
						   type => 'number',
						   category => "Annotation Page" },
	   "ComparedRegionsDefaultSizeRegions" => { value => 16000,
						    description => "default size of regions",
						    type => 'number',
						    category => "Annotation Page" },
	   "ComparedRegionsFocusTab" => { value => 'graphical',
					  description => "default tab to show (graphical/tabular)",
					  type => 'list',
					  entries => [ 'graphical', 'tabular' ],
					  category => "Annotation Page"},
	   "DisplayAliasInfo" => { value => 'hide',
				   description => "alias information for current feature",
				   type => 'list',
				   entries => [ 'hide', 'show' ],
				   category => "Annotation Page",
				   },
	   "DisplayAuxRoles" => { value => 'hide',
				  description => "display subsystem information for auxiliary roles",
				  type => 'list',
				  entries => [ 'hide', 'show' ],
				  category => "Annotation Page",
				  visibility => "annotator" },
	   "WebServicesKey" => { value => "",
				 description => "authentication key for web services",
				 type => 'generator',
				 generator => "web_services_key_generator",
				 category => "Web Services",
				 info => "<b>Note:</b> Creating a new key and clicking 'set preferences'<br>will render the previous key deprecated.<br>For more information on WebServices click <a href='http://ws.nmpdr.org/' target=_blank>here</a>" },
	   "show_hide_minus_one" => { value => 'hide',
				      type => 'list',
				      entries => [ 'hide', 'show' ],
				      description => "show/hide -1 variants default",
				      category => "Subsystem Editor Spreadsheet",
				      visibility => "annotator" },
	   "FeatureTableAliasColumn" => { value => 'hide',
					  type => 'list',
					  entries => [ 'hide', 'show' ],
					  description => "show/hide the alias column",
					  category => "Feature Table" },
	   "AdminUsersSeeAllJobs" => { value => "yes",
				       type => "list",
				       entries => ["yes", "no"],
				       description => "show all jobs",
				       category => "RAST Administrator Preferences",
				       admin_only => 'RAST'},
	   "AdminStartingJob" => { value => 1,
				   type => "number",
				   description => "display jobs starting at",
				   category => "RAST Administrator Preferences",
				   admin_only => 'RAST'},
	 };
}

sub web_services_key_generator {
  my ($self) = @_;

  my $application = $self->application();
  my $cgi = $application->cgi();

  my $name = $cgi->param('name');
  my $key = $cgi->param('key');

  my $master = $application->dbmaster();
  my $user = $application->session->user();

  my $generated = "";
  my $possible = 'abcdefghijkmnpqrstuvwxyz23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  while (length($generated) < 25) {
    $generated .= substr($possible, (int(rand(length($possible)))), 1);
  }
  my $preference = $master->Preferences->get_objects( { value => $generated } );

  while (scalar(@$preference)) {
    $generated = "";
    while (length($generated) < 25) {
      $generated .= substr($possible, (int(rand(length($possible)))), 1);
    }
    $preference = $master->Preferences->get_objects( { value => $generated } );
  }
  
  my $content = "<input id='pref_val_$name' type='text' readOnly=1 name='$name' size=25 value='" . $generated . "'>";
  if ($self->application->backend->name eq 'MGRAST' || $self->application->backend->name eq 'RNASEQRAST') {
    my $timeout = 604800;
    my $tdate = time + $timeout;
    my ($sec,$min,$hour,$mday,$mon,$year) = localtime($tdate);
    my $tdate_readable = ($year + 1900)." ".sprintf("%02d", $mon + 1)."-".sprintf("%02d", $mday)." ".sprintf("%02d", $hour).":".sprintf("%02d", $min).".".sprintf("%02d", $sec);
    $content .= "<input id='pref_val_WebServiceKeyTdate' type='hidden' name='WebServiceKeyTdate' value='$tdate'><br><br><b>webkey termination date</b> <input type='text' readOnly=1 size=20 value='" . $tdate_readable . "'>";
  }

  return $content;
}

sub required_rights {
  my ($self) = @_;

  my $user = '-';
  if ($self->application->session->user) {
    $user = $self->application->session->user->_id;
  }
  
  return [ [ 'edit', 'user', $user ] ];
}
