package WebPage;

use strict;
use warnings;

1;

=pod

=head1 NAME

WebPage - an abstract object for web pages used by WebApplication. 
Instances of this object each represent a distinct page.

=head1 DESCRIPTION

TODO

=head1 METHODS

=over 4

=item * B<new> ()

Creates a new instance of the WebPage object.

=cut

sub new {
  my ($class, $application) = @_;

  my $self = { application => $application,
	       title => '',
	       components => {},
	       css => [],
	       omit_from_session => undef,
	       javascript => [],
	       data => {},
           childComponents => [],
           _orderedCSS => [],
           _orderedJS  => [],
	     };

  bless($self, $class);

  return $self;
}


=pod

=item * B<title> ()

Get/set the title of a page. By default the title is empty.

=cut

sub title {
  my ($self, $title) = @_;
  if (defined $title) {
    $self->{'title'} = $title;
  }
  return $self->{'title'};
}


=pod

=item * B<init> ()

This method is called immediately after the new page object was created. 
It should be used to perform all initialisations (requesting web components,
registering actions, getting PPO connections) and include required css or
javascript files (rf. to B<require_javascript> and B<require_css>).

The default init does nothing.

=cut

sub init {

}


=pod

=item * B<output> ()

Returns the html output of the page. This method is abstract and must be 
implemented.

=cut

sub output {
  my ($self) = @_;

  die 'Abstract method "output" must be implemented in __PACKAGE__.\n';
}


=pod

=item * B<application> ()

Returns the reference to the WebApplication object which called this WebPage

=cut

sub application {
  return $_[0]->{application};
}

sub app {
  return $_[0]->{application};
}


=pod

=item * B<name> ()

Returns the page name which is used to retrieve this page using the 
cgi param 'page';

=cut

sub name {
  my $name = '';
  if(ref($_[0]) =~ /^\w+\:\:\w+\:\:(\w+)$/) {
    $name = $1;
  } elsif (ref($_[0]) =~ /^\w+\:\:(\w+)$/) {
    $name = $1;
  }
  return $name;
}


=pod

=item * B<url> ()

Returns the name of the cgi script of this page; 
this is used as a relative url 

=cut

sub url {
  my ($self) = @_;
  return $self->application->url . "?page=" . $self->name . "&";
}


=pod

=item * B<require_javascript> (I<js_file>)

Returns a reference to an array of javascript files to include into the output of 
the html page. If the optional parameter I<js_file> is given, the page will require 
that javascript file. To add a list of files, let I<js_file> be an array reference
of file names.

Call this method in the init method of your derived WebPage to include javascript 
files into your page. 

=cut

sub require_javascript {
  if ($_[1]) {
    if (ref $_[1] eq 'ARRAY') {
      $_[0]->{'javascript'} = $_[1];
    }
    else {
      push @{$_[0]->{'javascript'}}, $_[1];
    }
  }
  return $_[0]->{'javascript'};
}

=item * B<require_javascript_ordered> ([filenames]) || (filename)

Adds a list of javascript files or a single file to an ordered list that
are required for this component. These files are always added after the
files in the component's child-components.

=cut

sub require_javascript_ordered {
  my ($self, $files) = @_;
  if (ref($files) eq 'ARRAY') {
     push(@{$self->{"_orderedJS"}}, @$files);
  } else {
     push(@{$self->{"_orderedJS"}}, $files);
  }
  return $self->{"_orderedJS"};
}

=pod

=item * B<require_css> (I<css_file>)

Returns a reference to an array of css files to include into the output of the 
html page. If the optional parameter I<css_file> is given, the page will require 
that css file. To add a list of files, let I<css_file> be an array reference
of file names.

Call this method in the init method of your derived WebPage to include css files 
into your page.

=cut

sub require_css {
  if ($_[1]) {
    if (ref $_[1] eq 'ARRAY') {
      $_[0]->{'css'} = $_[1];
    }
    else {
      push @{$_[0]->{'css'}}, $_[1];
    }
  }
  return $_[0]->{'css'};
}

=item * B<require_css_ordered> ([filenames]) || (filename)

Adds a list of css files or a single file to an ordered list that
are required for this component. These files are always added after the
files in the component's child-components.

=cut

sub require_css_ordered {
  my ($self, $files) = @_;
  if (ref($files) eq 'ARRAY') {
     push(@{$self->{"_orderedCSS"}}, @$files);
  } else {
     push(@{$self->{"_orderedCSS"}}, $files);
  }
  return $self->{"_orderedCSS"};
}

=pod

=item * B<start_form> (I<id>, I<state>, I<target>)

Returns the start of a form

Parameters:

id - (optional) an html id that can be referenced by javascript
state - (optional) a hashref whose keys will be turned into the names of hidden
variables with the according values set as values. If this is 1 and not a hashref,
all key/value pairs of the CGI object of the previous invocation of the script
are preserved.
target - (optional) the name of the target window for this form

=cut

sub start_form {
  my ($self, $id, $state, $target) = @_;
  
  my $id_string = ($id) ? " id='$id'" : '';

  my $target_string = "";
  if (defined($target)) {
    $target_string = " target=$target";
  }

  my $start_form = "<form method='post'$id_string enctype='multipart/form-data' action='".
    $self->application->url . "' style='margin: 0px; padding: 0px;'$target_string>\n";  
  
  my $cgi = $self->application->cgi;
  if (ref($state) eq 'HASH') {

    foreach my $key (keys(%$state)) {

	if ( ref($state->{$key}) eq 'ARRAY' ) {
	    foreach my $val ( @{$state->{$key}} ) {
		$start_form .= $self->application->cgi->hidden(-name=>$key, -id=>$key, -value=>$val, -override=>1) . "\n";
	    }
	} else {
	  if ($key && defined($state->{$key})) {
	    $start_form .= $self->application->cgi->hidden(-name=>$key, -id=>$key, -value=>$state->{$key}, -override=>1) . "\n";
	  }
	}
    }
    
    unless (exists $state->{page}) {
      $start_form .= $self->application->cgi->hidden(-name=>'page', -id=>'page', -value=>$self->name, -overrride=>1) . "\n";
    }
    
  } 
  elsif ($state) {
    my $cgi = $self->application->cgi;
    my @names = $cgi->param;
    foreach my $name (@names) {
      next if ($name eq 'action');
      $start_form .= $cgi->hidden(-name=>$name, -id=>$name, -value=>$cgi->param($name), -overrride=>1) . "\n";
    }
  }
  else {
    $start_form .= $cgi->hidden(-name=>'page', -id=>'page', -value=>$self->name, -overrride=>1) . "\n";
  }
  
  return $start_form;
}

=pod

=item * B<end_form> ()

Returns the end of a form

=cut

sub end_form {
  my ($self) = @_;
  
  return "</form>";
}

=pod

=item * B<required_rights> ()

Returns an empty array, should be overwritten by subclass if rights
are required to view the page.

=cut

sub required_rights {
  return [];
}

=pod

=item * B<omit_from_session> (I<boolean>)

Returns true if a page should not be stored in the history.

=cut

sub omit_from_session {
  my $self = shift;

  if (scalar(@_)) {
    $self->{omit_from_session} = shift;
  }

  return $self->{omit_from_session};
}


=pod

=item * B<supported_rights> ()

Returns a reference to an array of right object this page supports.
This method should be overwritten for any page that supports rights.

=cut

sub supported_rights {
  return [];
}


=pod

=item * B<data> (I<id>, I<value>)

Method to store and retrieve data within the page object. The parameter I<id>
is the key used to store/retrieve the data. If you provide I<value> the method
will store the data, if not the stored data will returned. 

=cut

sub data {
  my $self = shift;
  my $id = shift;

  unless ($id) {
    die "No id key for data given.";
  }

#  if ( $id and scalar(@_) == 0 and
#       !exists($self->{data}->{$id}) ) {
#    die "Retrieving unknown id key: $id.";
#  }

  if (scalar(@_)) {
    $self->{data}->{$id} = shift;
  }

  return $self->{data}->{$id};
}

=pod

=item * B<robot_content> ()

Returns the html which will only be printed if the user agent is a robot.
This should be overwritten if you want special content to be seen by bots
like i.e. GoogleBot only.

=cut

sub robot_content {
  return "";
}

=pod

=item * B<button> ($value, %options)

Returns the html for a submit button. The position parameter is the button value
(default C<Submit>). Any other properties can be added as part of the options hash.
No leading C<-> is necessary on the option name. Thus,

  $page->button('OK', name => 'frog')

will generate a button with a value of C<OK> and a name of C<frog>. Use this method
instead of CGI methods or raw literals in order to automatically include the button
style class.

To generate a pure button (as opposed to a submit button), specify

    type => 'button'

in the options.

=cut

sub button {
  my ($self, $value, %options) = @_;
  my $app = $self->{application};
  return $app->button($value, %options);
}


=pod

=item * B<register_component> ($Class, $id)
Registers WebComponent with the page. This is identical to the
WebApplication call, but preserves component dependencies.

=cut

sub register_component {
    my ($self, $component, $id) = @_;
    my $web_component = $self->application->register_component($component, $id);
    push(@{$self->{"childComponents"}}, $web_component);
    return $web_component;
}   

    
