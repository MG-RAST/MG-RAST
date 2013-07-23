package MGRAST::WebPage::ClaimToken;

use base qw( WebPage );

use strict;
use warnings;

use WebConfig;
use Conf;

1;

=pod

=head1 NAME

ClaimToken - an instance of WebPage which lets the user claim an invitation to view data

=head1 DESCRIPTION

Display a page to claim invitation tokens

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Claim Token');
  
  return 1;
}


=pod

=item * B<output> ()

Returns the html output of the ClaimToken page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;

  my $token = $cgi->param('token');
  
  unless ($token) {
    $application->add_message('warning', "invalid token");
    return "";
  }

  my $content = "<h3>Claim Token</h3>";

  my $master = $application->dbmaster;
  my $token_scope = $master->Scope->get_objects( { name => 'token:'.$token } );
  if (scalar(@$token_scope)) {
    $token_scope = $token_scope->[0];
  } else {
    $content .= "<p>Your invitation was not found in the database. Please ask the person that sent you the invitation to resend it.</p>";
    return $content;
  }

  my $user = $application->session->user;
  if ($user) {
    my $uscope = $user->get_user_scope;
    my $rights = $master->Rights->get_objects( { scope => $token_scope } );
    my $metagenome_id = $rights->[0]->data_id;
    my $link = "MetagenomeOverview&metagenome=$metagenome_id";
    my $pscope = undef;
    if ($rights->[0]->data_type eq 'project') {
      $link = "MetagenomeProject&project=$metagenome_id";
      $pscope = $master->Scope->init( { application => undef,
					name => 'MGRAST_project_'.$metagenome_id } );
    }
    if ($token_scope->description && $token_scope->description =~ /^Reviewer_/) {
      $master->UserHasScope->create( { granted => 1,
				       scope => $token_scope,
				       user => $user } );
    } else {
      foreach my $right (@$rights) {
	$right->scope($uscope);
      }
      $token_scope->delete();
    }
    if ($pscope) {
      $master->UserHasScope->create( { granted => 1,
				       scope => $pscope,
				       user => $user } );
    }
    $content .= "<p style='width: 800px;'>You have successfully claimed your invitation. To view the data click <a href='metagenomics.cgi?page=$link'>here</a>.</p>";
  } else {
    $content .= "<p style='width: 800px;'>To claim your invitation, please log in. You can find the login box at the top right corner of the screen.<br><br>If you do not yet have an account, please register <a href='metagenomics.cgi?page=Register'>here</a>. Once your account is created, you can claim your invitation.</p>";
  }
  
  return $content;
}
