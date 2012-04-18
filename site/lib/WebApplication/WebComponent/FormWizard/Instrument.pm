package WebComponent::FormWizard::Instrument;

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
    my $fname   = "Function" . $name;

    $fname =~ s/[\s_-]//g;

    my $IDmodel = $fname . "model";
    my $IDmake  = $fname . "make";
    my $IDall   = $fname . "all";
    my $scripts = qq~
<script>
function $fname () {
  var Make  = document.getElementById("$IDmake");
  var Model = document.getElementById("$IDmodel");
  var All   = document.getElementById("$IDall");
  All.value = Make.value + " ; " + Model.value;
}
</script>~; 
  
    my ($make, $model) = split(/ ; /, $default) || ('', '');
    my $content = qq~
$scripts
<table><tr>
  <td>Make</td>
  <td><input type='text' id='$IDmake' name='${name}_make' value='$make' onchange='$fname();' /></td>
</tr><tr>
  <td>Model</td>
  <td><input type='text' id='$IDmodel' name='${name}_model' value="$model" onchange='$fname();' /></td>
</tr></table>
<input type='hidden' name='$name' id='$IDall' value='$default'>
~;

    return $content;
}

1;
