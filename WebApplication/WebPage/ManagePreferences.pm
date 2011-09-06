package WebPage::ManagePreferences;

use strict;
use warnings;

use base qw( WebPage );

use Global_Config;
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
  my $user_status = 'normal';
  if ($user && $user->has_right(undef, 'annotate', 'genome', '*')) {
    $user_status = 'annotator';
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
      $editable_preferences->{$pref->name}->{value} = $pref->value;
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
      if (exists($prefs{$param})) {
	$prefs{$param}->value($cgi->param($param));
      } else {
	$application->dbmaster->Preferences->create( { user => $user,
						       name => $param,
						       value => $cgi->param($param) } );
      }
    }
  }
  $self->{prefs} = $self->application->dbmaster->Preferences->get_objects( { user => $self->app->session->user() } )
}

sub editable_preferences {
  my ($self) = @_;

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
