package WebComponent::EventManager;

use strict;
use warnings;
use base qw( WebComponent );

use JSON;

1;

=pod

=head1 NAME

=head1 DESCRIPTION

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
    my $self = shift->SUPER::new(@_);
    my $app = $self->application();
    $self->{events} = {};
    $self->{raised} = "";
    $self->{eventResults} = "";
    return $self;
}

=item * B<output> ()

Returns the html/javascript required to run the ajax calls

=cut

sub output {
    my ($self) = @_;
    my $jsCalls = '';
    # Initialize EV js
    # added this directly to js file to make sure it's initialized first
    # $jsCalls .=  "if(EM==undefined){EM = new EventManager();}";
    # Add events and listenters to page
    foreach my $event (keys %{$self->{events}}) {
        for(my $i=0; $i<@{$self->{events}->{$event}}; $i++) {
            my $tmp = $self->_registerListener($event, $self->{events}->{$event}->[$i]);
            $jsCalls .= $tmp;
        }
     }
    # Add raised results if we got them         # RAISE then ADD
    $jsCalls .= $self->{raised};
    # Add raised event results if we got them
    $jsCalls .= $self->{eventResults};
    my $output = "<img src='./Html/clear.gif' onLoad='$jsCalls' />";
    return $output;
}

=item * B<addEvent> (I<event>, I<ajaxCommand>)

Adds listener to event. If event does not yet exist, creates it.  Requires
two arguments: event and ajaxCommand.  Event is an identifer string for
the event. AjaxCommand is an array reference with the following schema:
 ["functionName", "targetId", "cgiString", "ComponentName|componentId" ]
Where component name is only needed if the function is in the component.
Cgi string is optional and any parameters in there will be overridden by
the event parameters that match it.

=cut

sub addEvent {
    my ($self, $event, $ajaxCommand) = @_;
    if(!defined($self->{events}->{$event})) {
        $self->{events}->{$event} = [];
    }
    push(@{$self->{events}->{$event}}, $ajaxCommand);
}


=item * B<raiseEvent> (I<event>, I<data>)

Issues the event. First executing all server side listeners and storing
the results.  Results are then returned. If called from the JavaScript
event handler, the returned results are then processed. If called by
another Perl function, the return value can be ignored if output()
is called later. Data, optional, is a hash ref that is passed to the
handlers.

=cut

sub raiseEvent {
    my ($self, $event, $data) = @_;
    if(not defined($data)) {    # Data and event from ajax cgi
        $data = $self->_dataFromCgi();
        $event = $data->{'event'};
        delete $data->{'event'};
    }
    my $rtv = "";
    if(!defined($self->{events}->{$event})) {
        $self->{events}->{$event} = [];
    }
    my $ajaxCommands = $self->{events}->{$event};
    for(my $i=0; $i<@$ajaxCommands; $i++) {
        $rtv .= $self->_processAjaxCommand($ajaxCommands->[$i], $data);
    }
    $self->{eventResults} .= $rtv;
    $self->{raised} .= $self->_sendEventToClient($event, $data);
    return $rtv;
}

################################# 
#                               #
#       Helper Functions        #
#                               #
#################################
sub _processAjaxCommand {
    my ($self, $command, $data) = @_;
    my $app = $self->application();
    my %commandCgi;
    # Get predefined CGI if it exists
    my $cgiPositionInCommand = undef;
    my $componentPositionInCommand = undef;
    if (@$command == 3) {
        if ($command->[2] =~ m/=/) {
            $cgiPositionInCommand = 2;     
        } else {
            $componentPositionInCommand = 2;
        }
    } elsif(@$command == 4) {
        $cgiPositionInCommand = 2;     
        $componentPositionInCommand = 3;
    }
        
    if(defined($cgiPositionInCommand)) {   
        %commandCgi = split(/[&=]/, $command->[$cgiPositionInCommand]);
    }
    # Turn data into CGI 
    foreach my $key (keys %$data) {
        my $val = $data->{$key}; 
        if (ref($data->{$key}) eq 'ARRAY' ) {
            $val = join(',', @{$data->{$key}});
        }
        $commandCgi{$key} = $val;
    }
    if(defined($componentPositionInCommand)) { # Add component info if given (how Ajax takes it)
        $commandCgi{'component'} = $command->[$componentPositionInCommand];
    }
    my $dataCgi = [];
    my @tmp = %commandCgi;
    for(my $i=0; $i<(@tmp); $i+2) {
        my $j = $i+1;
        push(@$dataCgi, $tmp[$i].'='.$tmp[$j]);
    }
    my $dataStr = join('&', @$dataCgi); 
    # Call ajax function
    my $ajax = $self->_ajax();
    my $newCgi = CGI->new($dataStr);
    my $appName = $app->{'backend'}->name();
    my $pageName = $app->{'page'};
    my $html = $ajax->render($appName, $pageName, $command->[0], $newCgi);
    # Format result
    return $html;
}

sub _sendEventToClient {
    my ($self, $event, $data) = @_;
    # Do stuff
    my $dataFunc = '';
    if (ref($data) eq 'HASH') {
        foreach my $key (keys %$data) {
            if (len($dataFunc) != 0) {
                $dataFunc .= '&';
            }
            $dataFunc .= $key . '=' . $data->{$key};
        }
    } else {
        $dataFunc = $data;
    }
    return "EM.raiseEvent(\"".$event."\", \"".$dataFunc."\");";
}

sub _ajax {
    my ($self) = @_;
    my $app = $self->application();
    if (defined($app->{components}->{"Ajax"})) {
        return $app->{components}->{"Ajax"}->[0];
    } else {
        warn "Unable to find required ajax component in Event Handler!";
    }
}

sub _dataFromCgi {
    my ($self) = @_;
    my $returnDict = {};
    my $cgi = $self->application()->cgi();
    my @names = $cgi->params();
    foreach my $name (@names) {
        $returnDict->{$name} = $cgi->param($name);
    }
    return $returnDict;
}

sub _registerListener {
    my ($self, $event, $ajaxCommandOrJavascript) = @_;
    if(ref($ajaxCommandOrJavascript) eq 'ARRAY') {
        return "EM.addEvent(\"".$event."\", [".join(',', map('"'.$_.'"', @$ajaxCommandOrJavascript))."]);";
    } else {
        return "EM.addEvent(\"".$event."\", $ajaxCommandOrJavascript );";
    }
}
        
sub require_javascript {
  return ["$Conf::cgi_url/Html/EventManager.js"];
}
