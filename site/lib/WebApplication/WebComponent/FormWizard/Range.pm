package WebComponent::FormWizard::Range;

sub new {
    my ($class, $wizard, $question, $unit, $value) = @_;
    my $self = { question => $question,
		 value    => $value || '',
		 wizard   => $wizard,
		 unit     => $unit || '',
	     };

    bless $self;
    return $self;
}

sub unit {
    my ($self, $unit) = @_;
 
    if ($unit) {
      $self->{unit} = $unit
    }
    return $self->{unit};
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
    my $name    = $question->{name} ? $question->{name} : '';
    my $fname   = "Function" . $name;

    $fname =~ s/[\s_-]//g;

    my $IDmin   = $fname."min";
    my $IDmax   = $fname."max";
    my $IDall   = $fname."all";
    my $scripts = qq~
<script>
function $fname () {
  var Min   = document.getElementById("$IDmin");
  var Max   = document.getElementById("$IDmax");
  var All   = document.getElementById("$IDall");
  All.value = Min.value + " ; " + Max.value;
}
</script>~; 

    my ($min, $max) = split(/ ; /, $default) || ('', '');
    my $content = qq~
$scripts
<table><tr>
  <td>from </td>
  <td><input type='text' id='$IDmin' name='${name}_min' value='$min' onchange='$fname();' /></td>
</tr><tr>
  <td>to </td>
  <td><input type='text' id='$IDmax' name='${name}_max' value='$max' onchange='$fname();' /></td>
</tr></table>
<input type='hidden' name='$name' id='$IDall' value='$default'>
~;

    return $content;
}

1;
