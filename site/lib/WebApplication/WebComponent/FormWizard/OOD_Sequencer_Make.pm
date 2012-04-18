package WebComponent::FormWizard::OOD_Sequencer_Make;

use strict;
use warnings;
use Data::Dumper;
use CGI;
use WebComponent::FormWizard::OOD_List;

 
sub new{
    my ($class , $wizard , $question , $value) = @_;
    my $self = { question => $question ,
		 value    => $value || '' ,
		 wizard   => $wizard,
		 page     => $wizard->page,
	     };

    bless $self;
    return $self;
}

sub question{
    my ($self,$question) = @_;

    if ($question and ref $question){
	$self->{question} = $question
    }

    return $self->{question};
}

sub page{
  my ($self) = @_;
  return $self->{page};
}

sub wizard{
    my ($self,$wizard) = @_;

    if ($wizard and ref $wizard){
        $self->{wizard} = $wizard
	}

    return $self->{wizard};
}

sub value{
    my ($self,$value) = @_;

    if ($value){
        $self->{value} = $value
	}

    return $self->{value};
}



sub output {
  my ($self) = @_;

   my $list = WebComponent::FormWizard::OOD_List->new( $self->wizard , $self->question , 'Sequencer_Make' , 'popup' , 1);
  return $list->output;
}


1;
