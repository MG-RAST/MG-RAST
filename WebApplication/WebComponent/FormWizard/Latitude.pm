package WebComponent::FormWizard::Latitude;

sub new {
    my ($class, $wizard, $question, $value) = @_;
    my $self = { question => $question ,
		 value    => $value || '',
		 wizard   => $wizard,
	       };

    bless $self;
    return $self;
}

sub question {
    my ($self, $question) = @_;

    if ($question and ref $question) {
      $Self->{question} = $question
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

sub unencode_value {
  my ($self, $value) = @_;

  unless (defined $value) { return undef; }

  my $neg = ($value =~ /^-/) ? 1 : 0;
  $value =~ s/^-//;
  $value =~ s/^+//;

  if ($value =~ /^\./) { $value = "0" . $value; }
  if ( (($value =~ /^\d+$/) || ($value =~ /^\d+\.\d+$/)) && ($value <= 90) ) {
    return $neg ? "-$value" : $value;
  }
  else {
    return undef;
  }
}

sub output {
    my ($self, $question, $value) = @_;

    $question = ($question and ref $question) ? $question : $self->question;

    my $default = $question->{default} ? $question->{default} : "";
    $default    = (ref($default) && (ref($default) eq 'ARRAY')) ? $default->[0] : $default;
    my $name    = $question->{name} ? $question->{name} : '';
    my $fname   = "Function" . $name;

    $fname =~ s/[\s_-]//g;

    my $IDdir = $fname . "direction";
    my $IDval = $fname . "value";
    my $IDall = $fname . "all";

    my ($value, $dir) = ('', '');

    if ($default && ($default > 0)) {
      $value = $default;
      $dir   = "N";
    }
    elsif ($default && ($default < 0)) {
      $value = -1 * $default;
      $dir   = "S";
    }

    # set options for select field
    my $option = "";
    foreach my $d ( ("", "N", "S") ) {
      if ($d eq $dir) { $option .= "<option selected='selected'>$d</option>\n"; }
      else            { $option .= "<option>$d</option>\n"; }
    }

    my $content = qq~
<script>
function $fname () {
  var Value     = document.getElementById("$IDval");
  var Direction = document.getElementById("$IDdir");
  var All       = document.getElementById("$IDall");

  if (Direction.value == "S" || Direction.value == "W") {
       All.value = "-" + Value.value;
  } else {
       All.value = Value.value;
  }
}
</script>
<input type='text' name='${name}_value' size='10' id='$IDval' value='$value' onchange='$fname();' /> &deg;
<select id='$IDdir' name='${name}_direction' onchange='$fname();'>
$option
</select>
<input type='hidden' name='$name' id='$IDall' value='$default' />
~;
    
    return $content;
}

1;
