package WebGD;

use strict;
use warnings;

use GD;
use GD::Polyline;
use base qw( GD::Image );

use CGI;
use MIME::Base64;
use File::Temp qw( tempfile );

use Conf;

$CGI::LIST_CONTEXT_WARN = 0;
$CGI::Application::LIST_CONTEXT_WARN = 0;

1;

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(@_);
  
  if (-f $_[0] && $_[0] =~ /png$/) {
	$self = $class->SUPER::newFromPng(@_);
  }

  if (-f $_[0] && ($_[0] =~ /jpg$/ || $_[0] =~ /jpeg$/)) {
  	$self = $class->SUPER::newFromJpeg(@_);
  }
  
  bless($self, $class);

  return $self;
}

sub newFromPng {
  my $class = shift;

  # for now this only works on filepath
  return undef unless(-f $_[0]);
  
  my $self = $class->SUPER::newFromPng(@_);
  
  bless($self, $class);

  return $self;
}


sub newFromJpeg {
  my $class = shift;

  # for now this only works on filepath
  return undef unless(-f $_[0]);
  
  my $self = $class->SUPER::newFromJpeg(@_);
  
  bless($self, $class);

  return $self;
}


sub image_src {
  my ($self) = @_;

  my $cgi = new CGI;
  my $image_link = "";
  my $user_agent = $ENV{HTTP_USER_AGENT};
  if ($user_agent =~ /MSIE/) {
    $user_agent = 'IE';
  }
  if ($user_agent eq 'IE' || $Conf::file_images_only) {
    my ($fh, $filename) = tempfile( TEMPLATE => 'webimageXXXXX', DIR => $Conf::temp, SUFFIX => '.png' );
    print $fh $self->png();
    close $fh;
    $filename =~ s/.*\/(\w+\.png)$/$1/;
    $image_link = $Conf::temp_url."/".$filename;
  } else {
    my $mime = MIME::Base64::encode($self->png(), "");
    $image_link = "data:image/gif;base64,$mime";
  }

  return $image_link;
}
