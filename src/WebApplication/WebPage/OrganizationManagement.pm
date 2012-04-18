package WebPage::OrganizationManagement;

use base qw( WebPage );

1;

use strict;
use warnings;

=pod

=head1 NAME

OrganizationManagement - an instance of WebPage with editing capabilities for Organizations

=head1 DESCRIPTION

Offers admins the ability to manage all organizations

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->application->register_component("Table", "OrganizationTable");
  $self->application->register_component("Table", "UserTable");
  $self->application->register_action($self, 'add_user', 'add_user');
  $self->application->register_action($self, 'delete_user', 'delete_user');
  $self->application->register_action($self, 'add_organization', 'add_organization');
  $self->application->register_action($self, 'edit_organization', 'edit_organization');
  $self->title('Organization Management');

  return 1;
}

=item * B<output> ()

Returns the html output of the OrganizationManagement page.

=cut

sub output {
  my ($self) = @_;

  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  # create the organization table
  my $org_table = $application->component("OrganizationTable");
  $org_table->columns( [ { name => "Name", sortable => 1, filter => 1 },
			 { name => "Abbreviation", sortable => 1, filter => 1 },
			 { name => "Country", sortable => 1, filter => 1, operator => 'combobox' },
			 { name => "City", sortable => 1, filter => 1 },
			 { name => "url", sortable => 1, filter => 1 },
			 { name => "location", filter => 1 },
			 { name => "edit" } ] );
  $org_table->show_select_items_per_page(1);
  $org_table->items_per_page(15);
  $org_table->show_top_browse(1);
  $org_table->show_bottom_browse(1);
  $org_table->width('600px');

  # fill the organization table with data
  my $orgs = $master->Organization->get_objects();
  my $data = [];
  my $lookup_tested = 0;
  foreach my $org (@$orgs) {
    my $name = $org->name || "";
    my $abbr = $org->abbreviation || "";
    my $country = $org->country || "";
    my $city = $org->city || "";
    my $url = $org->url || "";
    my $location = $org->location() || "";
    
    push(@$data, [$name, $abbr, $country, $city, $url, $location, "<a href='".$application->url."?page=OrganizationManagement&edit=".$org->_id()."'>edit</a>" ]);
  }
  $org_table->data($data);

  # check if we want to display a certain org
  my $org_user_info = "";
  if ($cgi->param('edit')) {

    # try to get the org from the db
    my $org = $master->Organization->get_objects( { _id => $cgi->param('edit') } );

    # we have the org, display it's details
    if (scalar(@$org)) {
      $org = $org->[0];
      
      # get all users for this org
      my @users = map { $_->user } @{$master->OrganizationUsers->get_objects( { organization => $org } )};
      my %uhash = map { $_->_id() => 1 } @users;

      my $user_table = $application->component("UserTable");
      $user_table->columns( [ { name => "firstname" },
			    { name => "lastname" },
			    { name => "login" },
			    { name => "delete" } ] );
      
      # add the user to the user table
      my $user_table_data = [];
      foreach my $user (@users) {
	push(@$user_table_data, [ $user->firstname, $user->lastname, $user->login, "<a href='".$application->url."?page=OrganizationManagement&delete_user=".$user->_id()."&edit=".$org->_id()."&action=delete_user'>delete</a>" ]);
      }

      # set user table params
      $user_table->data($user_table_data);
      $user_table->items_per_page(10);
      $user_table->show_top_browse(1);
      $user_table->show_bottom_browse(1);

      # create a form to add new users
      my $user_select = $self->start_form('add_user_form', { action => 'add_user',
							     edit   => $org->_id() } );
      # compile the list of users not yet in the org
      my $all_users = $master->User->get_objects();
      my $not_yet_users = [];
      foreach my $user (@$all_users) {
	unless ($uhash{$user->_id()}) {
	  push(@$not_yet_users, $user);
	}
      }
      @$not_yet_users = sort { lc($a->lastname) cmp lc($b->lastname) || lc($a->firstname) cmp lc($b->firstname) } @$not_yet_users;

      # put the not yet users in the select box
      $user_select .= "<select name='new_user'>";
      foreach my $user (@$not_yet_users) {
	$user_select .= "<option value='".$user->_id()."'>".$user->lastname.", ".$user->firstname."</option>";
      }
      $user_select .= "</select>";
      $user_select .= "<input type='submit' value='add'>".$self->end_form();

      # create an organism info
      my $org_info = $self->start_form('org_form', { action => 'edit_organization', edit => $org->_id() })."<table>";
      $org_info .= "<tr><th>Name</th><td><input type='text' name='name' value='".$org->name."'></td></tr>";
      $org_info .= "<tr><th>Abbreviation</th><td><input type='text' name='abbreviation' value='".$org->abbreviation."'></td></tr>";
      $org_info .= "<tr><th>Country</th><td><input type='text' name='country' value='".$org->country."'></td></tr>";
      $org_info .= "<tr><th>City</th><td><input type='text' name='city' value='".$org->city."'></td></tr>";
      $org_info .= "<tr><th>url</th><td><input type='text' name='url' value='".$org->url."'></td></tr>";
      $org_info .= "<tr><th>location</th><td><input type='text' name='location' value='".$org->location."'></td></tr>";
      $org_info .= "</table><br><input type='submit' value='change'>".$self->end_form();

      $org_user_info = "<div><h2>Details for ". $org->name() . "</h2><table><tr><td style='padding-right: 15px;'>".$org_info."</td><td><b>Member List</b><br>".$user_table->output()."<p><b>Add user: &nbsp;</b>".$user_select."</p></td></tr></table></div>";
    }

    # we could not get the org, throw a warning
    else {
      $application->add_message('warning', 'The requested Organization could not be found');
    }
  }

  # create a form to create a new organization
  my $new_org_form = "<h2>Create new Organization</h2>";
  $new_org_form .= $self->start_form('new_org_form', { action => 'add_organization' })."<b>Name</b>&nbsp;&nbsp;<input type='text' name='new_org'><input type='submit' value='create'>".$self->end_form()."<br><br>";

  # headline
  my $html = "";
  
  # print the user table
  $html .= $org_user_info;

  # print the form for creating a new organization
  $html .= $new_org_form;

  $html .= "<b>locate URL </b> <input type='text' id='locator'><input type='button' value='locate' onclick='execute_ajax(\"locate_url\", \"locator_target\", \"url=\"+document.getElementById(\"locator\").value);'><div id='locator_target'></div>";

  # print the organization table
  $html .= "<h2>Organization List</h2>".$org_table->output();
  
  return $html;
}

sub add_user {
  my ($self) = @_;
  
  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  # get the cgi params we expect
  my $user_id = $cgi->param('new_user');
  my $org_id = $cgi->param('edit');

  # fail if we lack params
  unless (defined($user_id) && defined($org_id)) {
    $application->add_message('warning', "To add a user to an organization you must specify both user and organization.");
    return 0;
  }

  # retrieve objects from params
  my $user = $master->User->get_objects( { _id => $user_id } );
  if (scalar(@$user)) {
    $user = $user->[0];
  } else {
    $application->add_message('warning', "Could not find user in database.");
    return 0;
  }
  my $org = $master->Organization->get_objects( { _id => $org_id } );
  if (scalar(@$org)) {
    $org = $org->[0];
  } else {
    $application->add_message('warning', "Could not find organization in database.");
    return 0;
  }

  # check if the user already is part of that organization
  if (scalar(@{$master->OrganizationUsers->get_objects( { user => $user, organization => $org } )})) {
    $application->add_message('warning', "User ".$user->firstname." ".$user->lastname." is already a member of ".$org->name.".");
    return 0;
  }

  # things seem sane, try to add the user to the org
  my $success = $master->OrganizationUsers->create( { user => $user, organization => $org } );
  if (ref($success)) {
    $application->add_message('info', "Added user ".$user->firstname." ".$user->lastname." to ".$org->name.".");
  } else {
    $application->add_message('warning', "Failed to add user ".$user->firstname." ".$user->lastname." to ".$org->name.".");
    return 0;
  }

  return 1;
}

sub delete_user {
  my ($self) = @_;
  
  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  # get the cgi params we expect
  my $user_id = $cgi->param('delete_user');
  my $org_id = $cgi->param('edit');

  # fail if we lack params
  unless (defined($user_id) && defined($org_id)) {
    $application->add_message('warning', "To delete a user to an organization you must specify both user and organization.");
    return 0;
  }

  # retrieve objects from params
  my $user = $master->User->get_objects( { _id => $user_id } );
  if (scalar(@$user)) {
    $user = $user->[0];
  } else {
    $application->add_message('warning', "Could not find user in database.");
    return 0;
  }
  my $org = $master->Organization->get_objects( { _id => $org_id } );
  if (scalar(@$org)) {
    $org = $org->[0];
  } else {
    $application->add_message('warning', "Could not find organization in database.");
    return 0;
  }

  # check if the user already is part of that organization
  my $entries = $master->OrganizationUsers->get_objects( { user => $user, organization => $org } );
  unless (scalar(@{$entries})) {
    $application->add_message('warning', "User ".$user->firstname." ".$user->lastname." is not a member of ".$org->name.".");
    return 0;
  }

  # things seem sane, delete the user from the org
  $entries->[0]->delete();
  $application->add_message('info', "Deleted user ".$user->firstname." ".$user->lastname." from ".$org->name.".");

  return 1;
}

sub add_organization {
  my ($self) = @_;
  
  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  # check if we have all params we need
  my $name = $cgi->param('new_org');
  unless (defined($name)) {
    $application->add_message('warning', "You must choose a name when creating a new organization.");
    return 0;
  }

  # check whether the name is unique
  my $existing = $master->Organization->init( { name => $name } );
  if (defined($existing)) {
    $application->add_message('warning', "An organization with the name '$name' already exists.");
    return 0;
  }

  # sanity checks complete, try to create the organization
  my $new_org = $master->Organization->create( { name => $name } );
  if (defined($new_org)) {
    $application->add_message('info', "Organization '$name' created successfully.");
    $cgi->param('edit', $new_org->_id());
  } else {
    $application->add_message('warning', "Could not create organization '$name'.");
    return 0;
  }
  
  return 1;
}

sub edit_organization {
  my ($self) = @_;
  
  # get the objects we need
  my $application = $self->application();
  my $cgi = $application->cgi();
  my $master = $application->dbmaster();

  # check the cgi params
  my $org_id = $cgi->param('edit');
  unless (defined($org_id)) {
    $application->add_message('warning', "No organization to edit defined.");
    return 0;
  }
  
  # get the org from the db
  my $org = $master->Organization->get_objects( { _id => $org_id } );
  if (scalar(@$org)) {
    $org = $org->[0];
  } else {
    $application->add_message('warning', "Could not get organization from database.");
    return 0;
  }

  # first check if the name has changed
  if ($cgi->param('name') && ($cgi->param('name') ne $org->name)) {
    
    # check if the new name is unique
    if ($master->Organization->init( { name => $cgi->param('name') } )) {
      $application->add_message('warning', "Could not change name because that name has already been taken.");
    } else {
      $org->name($cgi->param('name'));
      $application->add_message('info', "Name changed to ".$cgi->param('name'));
      $cgi->param('edit', $cgi->param('name'));
    }
  }
  
  # now check for any other changes
  if ($cgi->param('abbreviation')) {
    $org->abbreviation($cgi->param('abbreviation'));
    $application->add_message('info', "Abbreviation changed to ".$cgi->param('abbreviation'));
  }
  if ($cgi->param('country')) {
    $org->country($cgi->param('country'));
    $application->add_message('info', "Country changed to ".$cgi->param('country'));
  }
  if ($cgi->param('city')) {
    $org->city($cgi->param('city'));
    $application->add_message('info', "City changed to ".$cgi->param('city'));
  }
  if ($cgi->param('url')) {
    $org->url($cgi->param('url'));
    $application->add_message('info', "URL changed to ".$cgi->param('url'));
  }
  if ($cgi->param('location')) {
    $org->location($cgi->param('location'));
    $application->add_message('info', "Location changed to ".$cgi->param('location'));
  }

  return 1;
}

sub locate_url {
  my ($self) = @_;

  my $url = $self->application->cgi->param('url');
  $url =~ s/\/$//;
  $url =~ s/^http\:\/\///;
  my $ip = `nslookup $url | grep Add | grep -v '#' | cut -f 2 -d ' '`;
  my @lines = split /\n/, $ip;
  $ip = $lines[0];

  use HTTP::Request::Common;
  my $ua = LWP::UserAgent->new;
  my $retval = $ua->request(GET "http://www.netip.de/search?query=$ip");
  my $content = $retval->content();
  my ($lat) = $content =~ /var latitude = ([^;]+)/;
  my ($long) = $content =~ /var longitude = ([^;]+)/;
  my $latlong = "position: $lat, $long";
  return $latlong;
}

sub required_rights {
  return [ [ 'login' ], [ 'edit', 'user', '*' ] ];
}
