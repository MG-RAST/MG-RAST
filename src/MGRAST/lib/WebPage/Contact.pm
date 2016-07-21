package MGRAST::WebPage::Contact;

use base qw( WebPage );

use strict;
use warnings;

use Captcha::reCAPTCHA;
use Mail::Mailer;

1;

=pod

=head1 NAME

Contact - an instance of WebPage which shows contact information

=head1 DESCRIPTION

Display an contact page

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Contact Information');
  $self->{icon} = "<img src='./Html/mg-contact.png' style='width: 20px; height: 20px; padding-right: 5px; position: relative; top: -3px;'>";

  $self->application->register_action($self, 'try_contact', 'try_contact');
  
  return 1;
}


=pod

=item * B<output> ()

Returns the html output of the Contact page.

=cut

sub output {
  my ($self) = @_;

  my $content = "";
  
  if ($self->application->session->user) {
    $content .= "<p width=800px align=justify >If you have any questions, comments or concerns about the metagenomics analysis server, please direct them to our <a href='mailto:mg-rast\@rt.mcs.anl.gov'>help desk</a>. Please take a look at the <a href='ftp://ftp.metagenomics.anl.gov/data/manual/mg-rast-manual.pdf' target=_blank>manual</a> before submitting your help desk email. Emails to the help-desk will reach the entire team, please do not send email to individuals.</p>";
  } else {
    my $c = Captcha::reCAPTCHA->new;
    $content .= "<p width=800px align=justify >If you have any questions, comments or concerns about the metagenomics analysis server, use the form below to reach our help desk. Please take a look at the <a href='ftp://ftp.metagenomics.anl.gov/data/manual/mg-rast-manual.pdf' target=_blank>manual</a> before submitting your help desk email. Emails to the help-desk will reach the entire team, please do not send email to individuals.</p>";

    $content .= $self->start_form('contact_form', { action => 'try_contact' });
    $content .= "<br><table><tr><td><b>your email</b></td><td><input type='text' size='50' name='email'></td></tr>";
    $content .= "<tr><td><b>subject</b></td><td><input type='text' size='50' name='subject'></td></tr>";
    $content .= "<tr><td><b>your message</b></td><td><textarea cols='50' rows='15' name='message'></textarea></td></tr></table><br>";
    $content .= $c->get_html("6Lf1FL4SAAAAAO3ToArzXm_cu6qvzIvZF4zviX2z");
    $content .= "<input type='submit' value='send'>";
    $content .= $self->end_form();

  }

  $content .= "<p width=800px align=justify >You can also find the answers to frequently asked questions on our <a href='http://blog.metagenomics.anl.gov'>support page</a>.</p>";

  $content .= "<p width=800px align=justify>Though we constantly test and evaluate our software, we always appreciate your feedback to improve our services.</p>";

  $content .= "<p width=800px><br/><br/><br/><br/>Best Regards<br/><br/>Your MG-RAST development team</p>";

  return $content;
}

sub try_contact {
  my ($self) = @_;

  my $cgi = $self->application->cgi;

  my $c = Captcha::reCAPTCHA->new;
  
  my $challenge = $cgi->param('recaptcha_challenge_field');
  my $response = $cgi->param('recaptcha_response_field');
  
  # Verify submission
  my $result = $c->check_answer("6Lf1FL4SAAAAAIJLRoCYjkEgie7RIvfV9hQGnAOh", $ENV{'REMOTE_ADDR'},$challenge, $response);
  
  if ( $result->{is_valid} ) {
    
    my $mailer = Mail::Mailer->new();
    $mailer->open({ From    => $cgi->param('email'),
		    To      => "mg-rast\@mcs.anl.gov",
		    Subject => $cgi->param('subject'),
		  })
      or die "Can't open Mail::Mailer: $!\n";
    print $mailer $cgi->param('message');
    $mailer->close();
    $self->application->add_message('info', "your request has been sent successfully");
  } else {
    $self->application->add_message('warning', "reCaptcha check failed, please try again");
  }
  
  return 1;
}
