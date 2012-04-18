package WebComponent::FormWizard::Measurement_List;

sub new {
    my ($class, $wizard, $question, $value, $named) = @_;
    my $self = { question => $question,
		 value    => $value || '',
		 wizard   => $wizard,
                 named    => $named || 0
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

sub named {
    my ($self, $named) = @_;

    if (defined $named) {
      $self->{named} = $named
    }
    return $self->{named};
}

sub check_data {
  my ($self, $value, $fh) = @_;

  # value is file
  if (defined $fh) {
    my @values;
    while (my $line = <$fh>) {
      chomp $line;
      push @values, $line;
    }
    return \@values;
  }
  # val is array
  elsif ($value && (ref($value) eq "ARRAY")) {
    return $value;
  }
  # val is string
  elsif ($value && (! ref $value)) {
    return [$value];
  }
  else {
    return undef;
  }
}

sub output {
    my ($self, $question, $value) = @_;

    $question = ($question && ref($question)) ? $question : $self->question;

    my $named   = $self->named;
    my $default = $question->{default} ? $question->{default} : [];
    $default    = (ref($default) && (ref($default) eq 'ARRAY')) ? $default : [$default];
    my $units   = ($question->{unit} && (ref $question->{unit} eq 'ARRAY')) ? $question->{unit} : $self->default_units;
    my $name    = $question->{name} || '';
    my $fname   = "Function" . $name;

    $fname =~ s/[\s_-]//g;

    my $html  = qq(
<table id=${fname}table><tr>
  <td><select name="selectall_$name" id="${fname}sel" multiple="multiple" style="min-width:120px" size="10">
);

    foreach my $d ( @$default ) {
      my $txt = $d;
      $txt =~ s/ ; / /g;
      $html .= qq(<option selected="selected" value="$d">$txt</option>\n);
    }

    $html .= qq(</select></td>
  <td align="center" style="padding-left: 15px;">
    <input type="button" value=" <-- " id="${fname}add" /><br>
    <input type="button" value=" --> " id="${fname}del" /><br>
    <input type="button" value="Clear All" id="${fname}clear" />
  </td><td style="padding-left: 15px;">);

    if ($named) {
      $html .= qq(
    <table><tr>
    <td>Name:</td>
    <td style="padding-left: 10px;"><input type="text" name="${name}_name" size="15" id="${fname}name" value="" /></td>
    <td>&nbsp;</td></tr><tr>
    <td>Value:</td>
    <td style="padding-left: 10px;">);
    }

    $html .= qq(
    <input type="text" name="${name}_value" size="15" id="${fname}value" value="" />
  </td><td style="padding-left: 10px;">
);

    my $unit_select = '';
    my $unit_clear  = '';
    if (scalar @$units > 1) {
      $unit_clear  = qq(\$("#${fname}unit").val("");\n);
      $unit_select = qq(<select name="${name}_unit" id="${fname}unit">\n<option value="">Please Select</option>\n);
      foreach my $u (@$units) {
	$unit_select .= qq(<option value="$u">$u</option>\n);
      }
      $unit_select .= "</select>\n";
    }
    elsif (scalar @$units == 1) {
      $unit_select = qq($units->[0]\n<input type='hidden' name='${name}_unit' id='${fname}unit' value='$units->[0]' />\n);
    }
    
    $html .= "$unit_select</td>";
    if ($named) { $html .= "</tr></table>\n</td>"; }
    $html .= qq(
<td style="padding-left: 15px;">
  <input type="button" value="Upload File" id="${fname}upload" style="color: blue" />
</td></tr></table>
<div id="${fname}div">
  <input type="file" name="$name" size="30" id="${fname}file" />
  &nbsp;&nbsp;
  <input type="button" value="Input Text" id="${fname}input" style="color: blue" />
</div>
);

    my $n_test  = $named ? qq(\$("#${fname}name").val() &&) : "";
    my $n_val   = $named ? qq(\$("#${fname}name").val(),) : "";
    my $n_clear = $named ? qq(\$("#${fname}name").val("");) : "";
    my $content = qq(
<script type="text/javascript">
\$(document).ready( function() {
  ${fname}default();

  \$("#${fname}add").click( function() {
    if ( $n_test \$("#${fname}value").val() && \$("#${fname}unit").val() ) {
      var set = [ $n_val \$("#${fname}value").val(), \$("#${fname}unit").val() ];
      \$("#${fname}sel").append('<option selected="selected" value="'+set.join(" ; ")+'">'+set.join(" ")+'</option>');
      \$("#${fname}value").val("");
      $unit_clear$n_clear
    }
    return false;
  });
  \$("#${fname}del").click( function(){ \$("#${fname}sel option:selected").remove(); return false; });
  \$("#${fname}clear").click( function(){ ${fname}clearsel(); return false; });
  \$("#${fname}input").click( function(){ ${fname}default(); \$("#${fname}file").val(""); return false; });
  \$("#${fname}upload").click( function(){
    \$("#${fname}table").hide();
    \$("#${fname}div").show();
    ${fname}clearsel();
    return false;
  });

  function ${fname}clearsel() { \$("#${fname}sel option").remove(); }
  function ${fname}default() { \$("#${fname}table").show(); \$("#${fname}div").hide(); }
});
</script>
$html
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
