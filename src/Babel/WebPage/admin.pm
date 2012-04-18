package AnnotationClearingHouse::WebPage::admin;

use strict;
use warnings;

use FIG;

use base qw( WebPage );

1;

sub init{
    my ($self) = @_;

    $self->application->register_component('Table','Correspondences' );
    my $fig = new FIG;
    my $ach = $self->application->data_handle('ACH');
    $self->data('fig',$fig);
    $self->data('ach',$ach);

#    $self->application->register_action($self, 'update_correspondances', 'Submit selection');
}


sub output {
    my ($self) = @_;

    my $fig = $self->data('fig');
    my $cgi = $self->application->cgi();
    my $html = [];
    my $handled = $cgi->param('status') || '';

    return "TEST";
}

sub required_rights {
    return [ [ 'login'] , [ 'monitor'] ];
}

