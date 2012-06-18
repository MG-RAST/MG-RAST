package WebComponent;

# WebComponent - abstract web component class 

# $Id: WebComponent.pm,v 1.8 2011-02-18 18:30:19 devoid Exp $

use strict;
use warnings;
use Conf;

=pod

=head1 NAME

WebComponent - abstract web component class

=head1 DESCRIPTION

This module is the abstract WebComponent class used by the web application
framework. A web component is a reusable page element inherited from this
class. Each component is assigned an unique id (to support javascript 
operations on the components). 

Using a web component is done by requesting the component from the application,
then setting parameters as supported by the specific component and finally
returning the html output of the component.

=head1 METHODS

=over 4

=item * B<new> (I<application>, I<id>)

Creates a new instance of the WebComponent object. The constructor requires
a reference to the web application object and an (unique) id. Unique ids 
are used to manipulate html elements by javascript.

=cut

sub new {
    my ($class, $application, $id, $type) = @_;

    # check application
    unless (ref $application and $application->isa("WebApplication")) {
      die "Invalid application in __PACKAGE__ new.";
    }
    
    $id = '' unless (defined $id);
    my $sv_url = "$Conf::cgi_url/seedviewer.cgi";

    my $self = { 'application' => $application, 
                 'id'          => $id,
                 'css'         => undef,
                 'svURL'       => $sv_url,
                 'sigleton'    => 0,
                 '_type'       => $type,
                 'childComponents' => [],
                 '_orderedCSS' => [],
                 '_orderedJS' => [],
	       };
    bless $self, $class;

    return $self;
}


=pod

=item * B<application> ()

Returns the reference to the application object

=cut

sub application {
  return $_[0]->{'application'};
}


=pod

=item * B<svURL> ()

Returns the Seed Viewer URL

=cut

sub svURL {
    return $_[0]->{svURL};
}

=pod

=item * B<id> ()

Returns the numerical id of the web component

=cut

sub id {
  my ($self, $id) = @_;
  if (defined($id)) {
    $self->{'id'} = $id;
    $self->{'application'}->{'components'}->{$self->{_type}}->[$id] = $self;
    $self->{'application'}->{'component_index'}->{$self->{_id}} = $self;
  }
  return $self->{'id'};
}


=pod

=item * B<get_trigger> (I<action_name>)

Returns a unique cgi action param based on the I<action_name>.

=cut

sub get_trigger {
  return 'wac_'.$_[0]->id.'_'.$_[1];
}

=pod

=item * B<require_javascript> ()

Returns a reference to an array of javascript files to include into the 
output page. By default the method returns the reference to an empty 
array. Overload in inherited web components as needed.

=cut

sub require_javascript {
  return [ ];
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

Returns the name of the css file to include into the the html of the web component.
If the optional parameter I<css_file> is given, the component will require that
css file instead of the default one.

=cut

sub require_css {
  if ($_[1]) {
    $_[0]->{'css'} = $_[1];
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

=item * B<output> ()

Returns the html of the web component

=cut

sub output {
  die "Abstract method 'output' must be implemented in __PACKAGE__.\n";
}

=head3 JavaCall

    my $string = $comp->JavaCall($name => @parms);

Format a call to a java function. The parameters will all be converted to
string literals and assembled with the method name.

=over 4

=item name

Name of the Java method to call.

=item parms

A list of strings. The strings will be converted to Javascript string literals
and specified as parameters on the method call.

=item RETURN

Returns a string that can be used as an event parameter to call the specified
Javascript method passing in the specified literal values.

=back

=cut

sub JavaCall {
    # Get the parameters.
    my ($self, $name, @parms) = @_;
    # Quote the strings.
    my @literals;
    for my $parm (@parms) {
        $parm =~ s/\n/\\n/g;
        $parm =~ s/'/\\'/g;
        push @literals, "'$parm'";
    }
    # Assemble the call.
    my $retVal = "$name(" . join(", ", @literals) . ")";
    # Return the result.
    return $retVal;
}

=pod

=item * <register_component> (<CoponentName>, <id>)

Calls register_component() of WebApplication, but also
remembers the scope of the component; useful when you need
to resolve dependencies, e.g. for js or css.

=cut

sub register_component {
    my ($self, $component, $id) = @_;
    my $web_component = $self->application()->register_component($component, $id);
    push(@{$self->{"childComponents"}}, $web_component);
    return $web_component;
}


1;
