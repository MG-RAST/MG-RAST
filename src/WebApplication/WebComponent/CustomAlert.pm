package WebComponent::CustomAlert;

use strict;
use warnings;
use base qw( WebComponent );

1;

=pod

=head1 NAME

TabView - component for a tabular view

=head1 DESCRIPTION

WebComponent for a tabular view

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
    my $self = shift->SUPER::new(@_);

    $self->{name} = '';
    $self->{title} = '';
    $self->{content} = '';
    $self->{width} = 300;
    $self->{type} = 'alert';
    $self->{buttons} = ['Ok', 'Cancel'];
    $self->{form} = '';
    $self->{onclick} = ['', ''];

    return $self;
}

=item * B<output> ()

Returns the html output of the TabView component.

=cut

sub output {
    my ($self) = @_;

    # must have name
    if ($self->name() eq '') {
	die "CustomAlert component must have a name";
    }

    my $html;

    $html .= "<div style='width:" . $self->width() . "px; text-align: center;'>";
    unless ($self->title() eq '0') {
	$html .= "<h2>" . $self->title() . "</h2>";
    }

    # add content
    my $content = $self->content();

    $html .= "<div style='margin: 0px 14px;'>$content</div>";
    
    # customize the buttons
    my $remove = "removeCustomAlert(); ";
    my $type = $self->type();
    my $buttons = "<div style='margin: 14px;'>";
    if ($type eq 'alert') {
	my $onclick = $self->onclick()->[0];
	$onclick .= (substr($onclick, -1) eq ";") ? ' ' : '; ' if ($onclick ne '');
	$onclick .= $remove;
	$buttons .= "<button onclick='$onclick'>" . $self->buttons()->[0] . "</button>";
    } elsif ($type eq 'confirm') {
	my $form = ($self->form() ne '') ? ("document." . $self->form() . ".submit(); ") : "";
	my $onclick1 = $self->onclick()->[0];
	$onclick1 .= (substr($onclick1, -1) eq ";") ? ' ' : '; ' if ($onclick1 ne '');
	$onclick1 .= $form . $remove;
	my $onclick2 = $self->onclick()->[1];
	$onclick2 .= (substr($onclick2, -1) eq ";") ? ' ' : '; ' if ($onclick2 ne '');
	$onclick2 .= $remove;
	my $button1 = "<button onclick='$onclick1'>" . $self->buttons()->[0] . "</button>";
	my $button2 = "<button onclick='$onclick2'>" . $self->buttons()->[1] . "</button>";
	$buttons .= "$button1&nbsp;&nbsp;&nbsp;$button2";
    } else {
	die "Unknown CustomAlert type: $type.";
    }
    $buttons .= "</div>";

    # add buttons
    $html .= $buttons;

    $html .= "</div>";
    # escape quotes
    $html =~ s/"/~!/g; #"

    return "<img src=\"./Html/clear.gif\" onload=\"CustomAlert['".$self->name()."'] = &quot;$html&quot;;\" />";
}

sub title {
    my ($self, $title) = @_;

    if (defined($title)) {
	$self->{title} = $title;
    }

    return $self->{title};
}

sub content {
    my ($self, $content) = @_;

    if (defined($content)) {
	$self->{content} = $content;
    }

    return $self->{content};
}

sub width {
    my ($self, $width) = @_;

    if (defined($width)) {
	$self->{width} = $width;
    }

    return $self->{width};
}

sub type {
    my ($self, $type) = @_;

    if (defined($type)) {
	$self->{type} = $type;
    }

    return $self->{type};
}

sub buttons {
    my ($self, $buttons) = @_;

    if (defined($buttons)) {
	$self->{buttons} = $buttons;
    }

    return $self->{buttons};
}

sub form {
    my ($self, $form) = @_;

    if (defined($form)) {
	$self->{form} = $form;
    }

    return $self->{form};
}

sub onclick {
    my ($self, $onclick) = @_;

    if (defined($onclick)) {
	$self->{onclick} = $onclick;
    }

    return $self->{onclick};
}

sub name {
    my ($self, $name) = @_;

    if (defined($name)) {
	$self->{name} = $name;
    }

    return $self->{name};
}

sub require_javascript {
    return ["$Conf::cgi_url/Html/CustomAlert.js","$Conf::cgi_url/Html/fade.js"];
}
