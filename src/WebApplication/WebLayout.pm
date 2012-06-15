package WebLayout;

use strict;
use warnings;

use WebConfig;

use HTML::Template;

1;

=head3 new

    my $layout = WebLayout->new($tmpl_data);

Create a layout object. The layout object contains all the information
needed to assemble a web page from the caller-specified templates.

=over 4

=item tmpl_data

Information about where to get the templates. If omitted, then default templates are used.
If a string, then the string should be the name of the template file for the page body.
If a hash reference, then the C<body> member must be the string for the body template and
the C<frame> member must be the string for the frame template.

=item RETURN

Returns a blessed layout object initialized using the specified template strings.

=back

=cut
sub new {
  my ($class, $tmpl_path) = @_;
  my ($body, $frame);
  my $tmpl  = $tmpl_path || TMPL_PATH.'WebLayoutDefault.tmpl';
  if (ref $tmpl eq 'HASH') {
    my $bodyString = $tmpl->{body};
    my $frameString = $tmpl->{frame};
    $body = HTML::Template->new(scalarref => \$bodyString, die_on_bad_params => 0);
    $frame = HTML::Template->new(scalarref => \$frameString, die_on_bad_params => 0);
  } else {
    $body = HTML::Template->new(filename => $tmpl, die_on_bad_params => 0);
    $frame = HTML::Template->new(filename => TMPL_PATH . 'WebLayoutFrame.tmpl',
				 die_on_bad_params => 0);
  }

  my $self = { 'templates' => [],
	       'default_template' => $body,
	       'frame'      => $frame,
	       'title'      => '',
	       'javascript' => [], 
	       'css'        => [],
	       'meta'       => [],
	       'relocation' => "",
	       'page' => "",
	       'show_icon' => 0,
	       'icon_path' => '',
	     };

  bless($self, $class);

  return $self;
}

=head3 set_relocation

    $layout->set_relocation($prefix);

Specify the relocation rule for relative URLs in links added to the
header. The rule will change the value C<./> at the beginning of a URL to
the specified prefix.

=over 4

=item prefix

Relative URL prefix used to get back to the normal location.

=back

=cut

sub set_relocation {
    # Get the parameters.
    my ($self, $prefix) = @_;
    # Set the new relocation prefix.
    $self->{relocation} = $prefix;
}

=head3 relocate

    my $relocatedURL = $layout->relocate($url);

Relocate the specified URL using the stored relocation factor. The
relocation factor indicates the difference between the location of the
active CGI script and the expected CGI directory.

=over 4

=item url

URL to relocate.

=item RETURN

Returns a relocated URL. If the URL is absolute, it is unchanged. If it is relative, it
will be moved according to the instructions in the relocation prefix.

=back

=cut

sub relocate {
    # Get the parameters.
    my ($self, $url) = @_;
    # Declare the return variable.
    my $retVal;
    # Determine the type of URL.
    if ($url =~ m#^(http|/)#) {
      # Here it's absolute, so we don't change it.
      $retVal = $url;
    } else {
      # Here it's relative. We need to relocate it. Strip off a dot-slash. This
      # is essentially a no-op.
      $url =~ s#^\./##;
      # Stash the relocation prefix in front.
      $retVal = $self->{relocation} . $url;
    }
    # Return the result.
    return $retVal;
}

sub set_content {
  $_[0]->frame->param( TITLE => $_[1]->{'title'} );

  my @warn = map { { MSG => $_ } } @{$_[1]->{'warnings'}};
  my @info = map { { MSG => $_ } } @{$_[1]->{'info'}};
  $_[0]->template->param( PAGETITLE => $_[1]->{'pagetitle'});
  $_[0]->template->param( CONTENT   => $_[1]->{'content'});
  $_[0]->template->param( MENU      => $_[1]->{'menu'});
  $_[0]->template->param( USER      => $_[1]->{'user'});
  $_[0]->template->param( WARNINGS  => \@warn );
  $_[0]->template->param( INFO      => \@info );

  while (my($var, $val) = each %Conf::web_template_settings)
  {
      $_[0]->template->param($var => $val);
  }
} 


sub set_variable {
  $_[0]->template->param( $_[1] => $_[2]);
}

sub set_page {
  my ($self, $page) = @_;
  $self->{page} = $page;
}

sub add_javascript {
  if ($_[1]) {
    push @{$_[0]->{'javascript'}}, { 'JSFILE' => $_[0]->relocate($_[1]) };
  }
}

sub add_css {
  if ($_[1]) {
    unshift @{$_[0]->{'css'}}, { 'CSSFILE' => $_[0]->relocate($_[1]) };
  }
}
sub add_css_reverse {
 if ($_[1]) {
    push @{$_[0]->{'css'}}, { 'CSSFILE' => $_[0]->relocate($_[1]) };
  }
}

sub add_metatag {
  if ($_[1]) {
    push @{$_[0]->{'meta'}}, { 'METATAG' => $_[1] };
  }
}

sub output {
  my ($self) = @_;
  my $retVal;
  $self->frame->param( BODY => $self->template->output() );
  $self->frame->param( JAVASCRIPT => $self->{'javascript'} );
  $self->frame->param( CSS => $self->{'css'} );
  $self->frame->param( META => $self->{'meta'} );
  $self->frame->param( SHOW_ICON => $self->show_icon );
  $self->frame->param( ICON_PATH => $self->icon_path );

  $retVal = $self->frame->output();
  return $retVal;
}

sub add_template {
  my ($self, $tmpl, $pages) = @_;
  my ($body);
  if (ref $tmpl eq 'HASH') {
    my $bodyString = $tmpl->{body};
    $body = HTML::Template->new(scalarref => \$bodyString, die_on_bad_params => 0);
  } else {
    $body = HTML::Template->new(filename => $tmpl, die_on_bad_params => 0);
  }
  push @{$self->{templates}}, [$body, $pages];
}

sub template {
  my ($self) = @_;
  unless(defined $self->{page}){
    return $self->{'default_template'};
  } else {
    foreach my $t (@{$self->{templates}}){
      foreach (@{$t->[1]}){
	if($self->{page} eq $_){
	  return $t->[0];
	}
      }
    }
  }
  return $self->{'default_template'};
}

sub frame {
  return $_[0]->{'frame'};
}

sub show_icon {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_icon} = $show;
  }

  return $self->{show_icon};
}

sub icon_path {
  my ($self, $path) = @_;

  if (defined($path)) {
    $self->{icon_path} = $path;
  }

  return $self->{icon_path};
}
