package WebComponent::FormWizard::Sex;

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

  $question = ($question && ref($question)) ? $question : $self->question;

  my $default = $question->{default} ? $question->{default} : "";
  $default    = (ref($default) && (ref($default) eq 'ARRAY')) ? $default->[0] : $default;

  my $name    = $question->{name} || '';
  my @gender  = ('Female','Male','Neuter','Hermaphrodite','Asexual','Not Determined');
  my $content = "<select name='$name'>\n<option value=''>Please select</option>\n";

  foreach my $sex (@gender) {
    my $selected = "selected='selected'" if ($sex eq $default);
    $content    .= "<option value='$sex' $selected>$sex</option>\n";
  }
  $content .="</select>\n";

  return $content;
}

1;
