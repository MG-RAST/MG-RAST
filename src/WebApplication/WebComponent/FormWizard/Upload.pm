package WebComponent::FormWizard::Upload;

sub new {
    my ($class, $wizard, $question, $value) = @_;
    my $self = { question => $question,
		 value    => $value || '',
		 wizard   => $wizard
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
  my ($self, $value, $fh, $dir) = @_;

  if ($value && (ref($value) eq "ARRAY")) { $value = $value->[0]; }
  my ($desc, $file) = $value ? split(/ ; /, $value) : ('', '');
  
  if ($desc && $file && $fh && (-d $dir) && rename($fh, "$dir/$file")) {
    return ["$desc ; $file"];
  }
  else {
    return undef;
  }
}

sub output {
  my ($self, $question, $value) = @_;

  $question = ($question && ref($question)) ? $question : $self->question;
  my $name  = $question->{name} || '';
  my $fname = "Function" . $name;
  $fname    =~ s/[\s_-]//g;

  my ($desc, $file) = $default ? split(/ ; /, $default) : ('', '');

  my $IDdesc  = $fname . "desc";
  my $IDfile  = $fname . "file";
  my $IDall   = $fname . "all";
  my $content = qq(
<script>
function $fname () {
  var Desc  = document.getElementById("$IDdesc");
  var File  = document.getElementById("$IDfile");
  var All   = document.getElementById("$IDall");
  All.value = Desc.value + " ; " + File.value;
}
</script>
<table><tr>
  <td>Description: </td>
  <td><input type='text' name='${name}_desc' size='20' id='$IDdesc' value='$desc' onchange='$fname();' /></td>
</tr><tr>
  <td>Upload: </td>
  <td><input type='file' name='${name}_file' id='$IDfile' value='$file' onchange='$fname();' /></td>
</tr></table>
<input type='hidden' name='$name' id='$IDall' value='$default' />
);

  return $content;
}

1;
