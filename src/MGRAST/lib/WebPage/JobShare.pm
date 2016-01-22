package MGRAST::WebPage::JobShare;

use base qw( WebPage );

1;

use strict;
use warnings;

use Mail::Mailer;
use WebConfig;
=pod

=head1 NAME

JobShare - an instance of WebPage to allow users to grant access to their genomes to others

=head1 DESCRIPTION

Offers the user the ability to grant access to his genomes

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Share a job');
  $self->application->register_action($self, 'share_job', 'share_job');
  $self->application->register_action($self, 'revoke_job', 'revoke_job');
  $self->application->register_action($self, 'cancel_token', 'cancel_token');
  $self->application->register_component('ListSelect', 'mgs');

  my $mgrast = $self->app->data_handle('MGRAST');

  # sanity check on job
  my $id = $self->application->cgi->param('metagenome') || '';
  my $job;
  eval { $job = $mgrast->Job->get_objects({ metagenome_id => $id })->[0]; };
  unless ($job) {
    $self->app->error("Unable to retrieve the job '$id'.");
  }
  $self->data('job', $job);

  my $data = [];
  my $mgids = $self->application->session->user->has_right_to(undef, 'edit', 'metagenome');
  foreach my $mgid (@$mgids) {
    next unless ($mgid =~ /\d+\.\d+/);
    my $j = $mgrast->Job->get_objects( { metagenome_id => $mgid } )->[0];
    next unless $j;
    push(@$data, { label => $j->name, value => $mgid });
  }
  $self->data('mgids', $data);
  
  return 1;
}

=item * B<output> ()

Returns the html output of the DelegateRights page.

=cut

sub output {
  my ($self) = @_;

  my $job = $self->data('job');

  my $mgrast = $self->app->data_handle('MGRAST');

  my $content = "";

  # short job info
  $content .= "<p> &raquo <a href='metagenomics.cgi?page=MetagenomeSelect'>Back to the Metagenome Select</a></p>";
  
  $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>Job Information</p>";
  $content .= "<table>";
  $content .= "<tr><th>Name - ID:</th><td>".$job->metagenome_id." - ".$job->name."</td></tr>";
  $content .= "<tr><th>Job:</th><td> #".$job->job_id."</td></tr>";    
  $content .= "<tr><th>User:</th><td>".$job->owner->login."</td></tr>";
  $content .= "</table>";

  my $user = $self->application->session->user;
  $content .= "<p><a style='cursor: pointer;' onclick='if(this.innerHTML==\"share multiple metagenomes\"){this.innerHTML=\"share single metagenome\";document.getElementById(\"multishare\").style.display=\"\";document.getElementById(\"domulti\").value=1;}else{this.innerHTML=\"share multiple metagenomes\";document.getElementById(\"multishare\").style.display=\"none\";document.getElementById(\"domulti\").value=0;}'>share multiple metagenomes</a></p><div id='multishare' style='display: none;'>";

  my $data = $self->data('mgids');
  my $list_select = $self->application->component('mgs');
  $list_select->data($data);
  $list_select->show_reset(1);
  $list_select->multiple(1);
  $list_select->filter(1);
  $list_select->left_header('available metagenomes');
  $list_select->right_header('selected metagenomes');
  $list_select->name('share_metagenomes');

  $content .= $self->start_form('share_job', { metagenome => $job->metagenome_id,
					       action => 'share_job' });


  $content .= $list_select->output()."<input type='hidden' name='multishare' id='domulti' value=0></div>";

  # short help text
  $content .= '<p style="width: 70%;">To share the above job and its data with another user, please enter the email address of the user. The user will receive an email that notifies him how to access the data. Once you have granted the right to view one of your MG-RAST jobs to another user or group, the name will appear at the bottom of the page with the option to revoke it.</p>';

  # select user or group
  $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>Enter an email address</p>";
  my $email = $self->app->cgi->param('email') || '';
  $content .= "<p><strong>Enter an email address:</strong> <input name='email' type='textbox' value='$email'></p>";
  $content .= "<p><input type='button' name='share_job' value=' Share job with this user or group ' onclick='list_select_select_all(\"".$list_select->id."\");document.forms.share_job.submit();'></p>";
  $content .= $self->end_form;
  
  # show people who can see this job at the moment
  $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>This job is currently available to:</p>";
  my $rights = $self->application->dbmaster->Rights->get_objects( { name => 'view',
								    data_type => 'metagenome',
								    data_id => $job->metagenome_id
								  });
  my $found_one = 0;
  $content .= '<table>';
  my $tokens = [];
  foreach my $r (@$rights) {
    next if ($self->app->session->user->get_user_scope->_id eq $r->scope->_id);
    if ($r->scope->name =~ /^token\:/) {
      push(@$tokens, $r->scope);
    } else {
      $content .= "<tr><td>".$r->scope->name_readable."</td>";
    }
    if($r->delegated) {
      $content .= "<td>".$self->start_form('revoke_job', { metagenome => $job->metagenome_id, 
							   action => 'revoke_job',
							   scope => $r->scope->_id,
							 });
      $content .= "<input type='submit' name='revoke_job' value=' Revoke '>";
      $content .= "</td>";
    }
    else {
      $content .= "<td></td>";
    }
    $content .= '</tr>';
    $found_one = 1;
  }
  
  unless($found_one) {
    $content .= "<tr><td>This job is not shared with anyone at the moment.</td></tr>";
  }
  $content .= '</table>';

  if (scalar(@$tokens)) {
    $content .= "<p id='section_bar'><img src='".IMAGES."rast-info.png'/>invitations which have not been claimed yet:</p>";
    $content .= "<table>";
    foreach my $token (@$tokens) {
      my ($uid, $date, $email) = $token->description =~ /^token_scope\|from_user\:(\d+)\|init_date:(\d+)\|email\:(.+)/;
      my $u = $self->application->dbmaster->User->get_objects( { _id => $uid } )->[0];
      my $t = localtime($date);
      my ($token_id) = $token->name =~ /^token\:(.+)$/;
      $content .= "<tr><td>sent by ".$u->firstname." ".$u->lastname." to $email on $t <input type='button' onclick='window.top.location=\"metagenomics.cgi?page=JobShare&job=".$job->job_id."&action=cancel_token&token=$token_id\"' value='cancel'></td></tr>";
    }
    $content .= "</table>";
  }

  return $content;
}

sub cancel_token {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  my $master = $application->dbmaster;

  my $token = $cgi->param('token');
  unless ($token) {
    $application->add_message('warning', "invalid token, aborting");
    return 0;
  }
  
  my $scope = $master->Scope->get_objects( { name => "token:".$token } );
  unless (scalar(@$scope)) {
    $application->add_message('warning', "token not found, aborting");
    return 0;
  }

  my $rights = $master->Rights->get_objects( { scope => $scope->[0] } );
  foreach my $r (@$rights) {
    $r->delete();
  }
  $scope->[0]->delete();

  $application->add_message('info', "invitation canceled");

  return 1;
}

=pod

=item * B<share_job>()

Action method to grant the right to view and edit a genome to the selected scope

=cut

sub share_job {
  my ($self) = @_;
  
  # get some info
  my $job_id = $self->data('job')->job_id;
  my $genome_id = $self->data('job')->metagenome_id;
  my $genome_name = $self->data('job')->name;
  my $application = $self->application;
  my $cgi = $application->cgi;
  my $master = $self->application->dbmaster;  

  # check email format
  my $email = $self->app->cgi->param('email');
  unless ($email =~ /^[\w\-\.]+\@[\.a-zA-Z\-0-9]+\.[a-zA-Z]+$/) {

    # check if this is a group
    my $checkscopes = $master->Scope->get_objects( { name => $email } );
    if (scalar(@$checkscopes)) {
      
      my $scope = $checkscopes->[0];

      # grant rights if necessary
      my $rights = [ 'view', 'edit' ];
      my $genome_ids = [ $genome_id ];
      if ($cgi->param('multishare') && $cgi->param('multishare') == 1) {
	@$genome_ids = $cgi->param('share_metagenomes');
      }
      foreach my $gid (@$genome_ids) {
	foreach my $name (@$rights) {
	  unless(scalar(@{$master->Rights->get_objects( { name => $name,
							  data_type => 'metagenome',
							  data_id => $gid,
							  scope => $scope } )})) {
	    my $right = $master->Rights->create( { granted => 1,
						   name => $name,
						   data_type => 'metagenome',
						   data_id => $gid,
						   scope => $scope,
						   delegated => 1, } );
	    unless (ref $right) {
	      $self->app->add_message('warning', 'Failed to create the right in the user database, aborting.');
	      return 0;
	    }
	  }
	}
      }
      
      $self->app->add_message('info', "Granted the right to view this job to the group ".$scope->name.".");
      return 1;
    }

    $self->application->add_message('warning', 'Please enter a valid email address. If you tried to share with a group, please check the spelling of the group.');
    return 0;
  }

  # check if have a user with that email
  my $user = $master->User->init({ email => $email });
  if (ref $user) {

    my $genome_ids = [ $genome_id ];    
    my $what = "$genome_name ($genome_id)";
    if ($cgi->param('multishare') && $cgi->param('multishare') == 1) {
      my $mgids = $self->data('mgids');
      my $mghash = {};
      %$mghash = map { $_->{value} => $_->{label} } @$mgids;
      @$genome_ids = $cgi->param('share_metagenomes');
      $what = "the metagenomes\n".join("\n", map { $mghash->{$_}." (".$_.")" } @$genome_ids);
    }

    # send email
    my $ubody = HTML::Template->new(filename => TMPL_PATH.'EmailSharedJobGranted.tmpl',
				    die_on_bad_params => 0);
    $ubody->param('FIRSTNAME', $user->firstname);
    $ubody->param('LASTNAME', $user->lastname);
    $ubody->param('WHAT', $what);
    $ubody->param('WHOM', $self->app->session->user->firstname.' '.$self->app->session->user->lastname);
    $ubody->param('LINK', $WebConfig::APPLICATION_URL."metagenomics.cgi?page=MetagenomeOverview&metagenome=$genome_id");
    $ubody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
    
    $user->send_email( $WebConfig::ADMIN_EMAIL,
		       $WebConfig::APPLICATION_NAME.' - new data available',
		       $ubody->output
		     );

    # grant rights if necessary
    my $rights = [ 'view', 'edit' ];
    foreach my $gid (@$genome_ids) {
      foreach my $name (@$rights) {
	unless(scalar(@{$master->Rights->get_objects( { name => $name,
							data_type => 'metagenome',
							data_id => $gid,
							scope => $user->get_user_scope } )})) {
	  my $right = $master->Rights->create( { granted => 1,
						 name => $name,
						 data_type => 'metagenome',
						 data_id => $gid,
						 scope => $user->get_user_scope,
						 delegated => 1, } );
	  unless (ref $right) {
	    $self->app->add_message('warning', 'Failed to create the right in the user database, aborting.');
	    return 0;
	  }
	}
      }
    }

    $self->app->add_message('info', "Granted the right to view this job to ".$user->firstname." ".$user->lastname.".");
    return 1;

  } else {

    if ($cgi->param('multishare') && $cgi->param('multishare') == 1) {
      $self->application->add_message('warning', "You can only share multiple metagenomes to an existing user.<br>Please ask the specified user to register at ".$WebConfig::APPLICATION_NAME." first. If the user has already registered, please ask him for the email address they registered with.");
      return 0;
    }
    
    # create a claim token
    my $description = "token_scope|from_user:".$application->session->user->{_id}."|init_date:".time."|email:".$email;
    my @chars=('a'..'z','A'..'Z','0'..'9','_');
    my $token = "";
    foreach (1..50) {
      $token.=$chars[rand @chars];
    }
    
    # create scope for token
    my $token_scope = $master->Scope->create( { name => "token:".$token, description => $description } );
    unless (ref($token_scope)) {
      $self->application->add_message('warning', "failed to create token");
      return 0;
    }

    # add rights to scope
    my $rights = [ 'view', 'edit' ];
    my $rsave = [];
    foreach my $name (@$rights) {
      my $right = $master->Rights->create( { granted => 1,
					     name => $name,
					     data_type => 'metagenome',
					     data_id => $genome_id,
					     scope => $token_scope,
					     delegated => 1, } );
      unless (ref $right) {
	$self->app->add_message('warning', 'Failed to create the right in the user database, aborting.');
	$token_scope->delete();
	foreach my $r (@$rsave) {
	  $r->delete();
	}
	return 0;
      }

      push(@$rsave, $right);
    }

    # send token mail
    my $ubody = HTML::Template->new(filename => TMPL_PATH.'EmailSharedJobToken.tmpl',
				    die_on_bad_params => 0);
    $ubody->param('WHAT', "$genome_name ($genome_id)");
    $ubody->param('REGISTER', $WebConfig::APPLICATION_URL."?page=Register");
    $ubody->param('WHOM', $self->app->session->user->firstname.' '.$self->app->session->user->lastname);
    $ubody->param('LINK', $WebConfig::APPLICATION_URL."?page=ClaimToken&token=$token");
    $ubody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
    

    my $mailer = Mail::Mailer->new();
    if ($mailer->open({ From    => $WebConfig::ADMIN_EMAIL,
		    To      => $email,
		    Subject => $WebConfig::APPLICATION_NAME.' - new data available',
		      })) {
      print $mailer $ubody->output;
      $mailer->close();
      $application->add_message('info', "invitation sent successfully");
    } else {
      $token_scope->delete();
      foreach my $r (@$rsave) {
	$r->delete();
      }
      $application->add_message('warning', "Could not send invitation mail, aborting.");
      return 0;
    }

    return 1;
  }

  return ;
}


=pod

=item * B<revoke_job>()

Action method to revoke the right to view and edit a genome to the selected scope

=cut

sub revoke_job {
  my ($self) = @_;

  my $master = $self->application->dbmaster;

  # get the scope
  my $s_id = $self->app->cgi->param('scope');
  my $scope = $master->Scope->get_objects({ _id => $s_id });
  unless(@$scope) {
    $self->app->add_message('warning', 'There has been an error: missing a scope to revoke right on., aborting.');
    return 0;
  }
  $scope = $scope->[0];

  # get genome id
  my $genome_id = $self->data('job')->metagenome_id;

  # delete the rights, double check delegated
  my $rights = [ 'view', 'edit' ];
  foreach my $name (@$rights) {
    foreach my $r (@{$master->Rights->get_objects( { name => $name,
						     data_type => 'metagenome',
						     data_id => $genome_id,
						     scope => $scope,
						     delegated => 1,
						   })}) {
      $r->delete;
    }
  }

  $self->app->add_message('info', "Revoked the right to view this job to ".$scope->name_readable.".");

  return 1;

}


=pod

=item * B<required_rights>()

Returns a reference to the array of required rights

=cut

sub required_rights {
  my $rights = [ [ 'login' ], ];
  if ($_[0]->data('job')) {
    push @$rights, [ 'edit', 'metagenome', $_[0]->data('job')->metagenome_id, 1 ];
  }
      
  return $rights;
}

