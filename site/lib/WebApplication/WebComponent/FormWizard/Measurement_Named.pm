package WebComponent::FormWizard::Measurement_Named;

use WebComponent::FormWizard::Measurement_List;

sub new {
  my ($class, $wizard, $question, $value) = @_;
  
  my $m_list = WebComponent::FormWizard::Measurement_List->new($wizard, $question, $value, 1);
  my $self = { question => $m_list->question,
	       value    => $m_list->value,
	       wizard   => $m_list->wizard,
	       m_list   => $m_list
	     };

  bless $self;
  return $self;
}

sub question {
    my ($self, $question) = @_;

    if ($question and ref $question) {
      $self->{question} = $question
    }
    return $self->{question};
}

sub wizard {
    my ($self, $wizard) = @_;

    if ($wizard and ref $wizard) {
      $self->{wizard} = $wizard
    }
    return $self->{wizard};
}

sub value {
    my ($self, $value) = @_;

    if ($value) {
      $self->{value} = $value
    }
    return $self->{value};
}

sub check_data {
  my ($self, $value) = @_;

  return $self->{m_list}->check_data($value);
}

sub output {
  my ($self, $question, $value) = @_;

  return $self->{m_list}->output($question, $value);
}

1;
