package WebComponent::FormWizard::Measurement;

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
    my ($self, $question) = @_;

    $question = ($question && ref($question)) ? $question : $self->question;

    my $default  = $question->{default} ? $question->{default} : '';
    $default     = (ref($default) && (ref($default) eq 'ARRAY')) ? $default->[0] : $default;
    my ($vd,$ud) = $default ? split(/ ; /, $default) : ('', '');
    my $name     = $question->{name} || '';
    my $fname    = "Function" . $name;

    $fname =~ s/[\s_-]//g;

    my $IDvalue = $fname . "value";
    my $IDunit  = $fname . "unit";
    my $IDall   = $fname . "all";
    my $units   = ($question->{unit} && (ref $question->{unit} eq "ARRAY")) ? $question->{unit} : $self->default_units;

    $ud      = $ud ? $ud : $units->[0];
    $default = ($vd && $ud) ? "$vd ; $ud" : '';

    my $unit_select = '';
    if (scalar @$units > 1) {
      $unit_select = "<select id='$IDunit' name='${name}_unit' onchange='$fname();'>\n<option value=''>Please Select</option>\n";
      foreach my $u (@$units) {
	if ($u eq $ud) { $unit_select .= "<option selected='selected' value='$u'>$u</option>\n"; }
	else           { $unit_select .= "<option value='$u'>$u</option>\n"; }
      }
      $unit_select .= "</select>";
    }
    elsif (scalar @$units == 1) {
      $unit_select  = "$ud\n<input type='hidden' name='${name}_unit' id='$IDunit' value='$ud' />";
    }

    my $content = qq(
<script>
function $fname () {
  var Value = document.getElementById("$IDvalue");
  var Unit  = document.getElementById("$IDunit");
  var All   = document.getElementById("$IDall");
  if ( Value.value && Unit.value ) {
    All.value = Value.value + " ; " + Unit.value;
  }
}
</script>
<input type='text' name='${name}_value' size='15' id='$IDvalue' value='$vd' onchange='$fname();' />
&nbsp;&nbsp;$unit_select
<input type='hidden' name='$name' id='$IDall' value='$default' />
);

    return $content;
}

sub default_units {
  my ($self) = @_;

  return [ "Meter",
	   "Kilogram",
	   "Liter",
	   "Second",
	   "Ampere",
	   "Celsius",
	   "Candela",
	   "Mole",
	   "Atmosphere",
	   "Percent"
	 ];
}

1;
