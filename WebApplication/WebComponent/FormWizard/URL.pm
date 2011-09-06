package WebComponent::FormWizard::URL;

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

    my $default = $question->{default} ? $question->{default} : "";
    $default    = (ref($default) && (ref($default) eq 'ARRAY')) ? $default->[0] : $default;
    my $name    = $question->{name} || "";

    return qq(
<table><tr>
  <td valign="top">http://</td>
  <td><textarea name='$name' value='$default' cols='21' rows='3'>$default</textarea></td>
</tr></table>
);
}

1;
