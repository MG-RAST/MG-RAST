package WebComponent::FormWizard::Boolean;

sub new {
    my ($class, $wizard, $question, $value) = @_;
    my $self = { question => $question,
		 value    => $value || '',
		 wizard   => $wizard,
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


sub output {
  my ($self, $question, $value) = @_;

  $question   = ($question && ref($question)) ? $question : $self->question;
  my $default = $question->{default} ? $question->{default} : '';
  $default    = ($default && (ref($default) eq 'ARRAY')) ? $default->[0] : $default;

  my $name = $question->{name} || '';
  my $bool = -1;

  if ($default ne '') {
    if    ( ($default == 1) || ($default =~ /yes/i) )       { $bool = 1; }
    elsif ( ($default == 0) || ($default =~ /(no|none)/i) ) { $bool = 0; }
  }

  return "<input type='radio' name='$name' value='1'" . (($bool == 1) ? " checked='checked'" : "") . " />Yes<br>" .
         "<input type='radio' name='$name' value='0'" . (($bool == 0) ? " checked='checked'" : "") . " />No";
}

1;
