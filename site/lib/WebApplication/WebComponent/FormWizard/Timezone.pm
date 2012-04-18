package WebComponent::FormWizard::Timezone;

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

  $question = ($question and ref $question) ? $question : $self->question;

  my $default = $question->{default} ? $question->{default} : "UTC";
  $default    = (ref($default) && (ref($default) eq 'ARRAY')) ? $default->[0] : $default;
  my $zones   = $self->timezones();
  my $content = "<select name='". $question->{name} ."'>";
  
  foreach my $z (@$zones) {
    my $select = ($default eq $z) ? " selected='selected'" : "";
    $content  .= "<option value='$z'$select>$z</option>";
  }
  $content .="</select>";

  return $content;
}

sub timezones {
  return [ 'UTC-11',
	   'UTC-10',
	   'UTC-9',
	   'UTC-8',
	   'UTC-7',
	   'UTC-6',
	   'UTC-5',
	   'UTC-4',
	   'UTC-3',
	   'UTC-2',
	   'UTC-1',
	   'UTC',
	   'UTC+1',
	   'UTC+2',
	   'UTC+3',
	   'UTC+4',
	   'UTC+5',
	   'UTC+6',
	   'UTC+7',
	   'UTC+8',
	   'UTC+9',
	   'UTC+10',
	   'UTC+11' ];
}

1;
