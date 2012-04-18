package MyApp::WebPage::MyFirstPage;

use strict;
use warnings;

use base qw( WebPage );

1;

sub output {
  my ($self) = @_;

  my $content = "<h1>Hello World</h1>";

  return $content;
}
