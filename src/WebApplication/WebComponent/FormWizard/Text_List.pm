package WebComponent::FormWizard::Text_List;

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

    my $default = $question->{default} ? $question->{default} : [];
    $default    = (ref($default) && (ref($default) eq 'ARRAY')) ? $default : [$default];
    my $name    = $question->{name} || '';
    my $fname   = "Function" . $name;

    $fname =~ s/[\s_-]//g;

    my $html  = qq(
<table id=${fname}table><tr>
  <td><select name="selectall_$name" id="${fname}sel" multiple="multiple" style="min-width:120px" size="10">
);

    foreach my $d ( @$default ) {
      my $txt = $d;
      $txt =~ s/ ; / /;
      $html .= qq(<option selected="selected" value="$d">$txt</option>\n);
    }

    $html .= qq(</select></td>
  <td align="center" style="padding-left: 15px;">
    <input type="button" value=" <-- " id="${fname}add" /><br>
    <input type="button" value=" --> " id="${fname}del" /><br>
    <input type="button" value="Clear All" id="${fname}clear" />
  </td><td style="padding-left: 15px;">
    <input type="text" name="${name}_value" size="25" id="${fname}value" value="" />
  </td><td style="padding-left: 15px;">
    <input type="button" value="Upload File" id="${fname}upload" style="color: blue" />
  </td>
</tr></table>
<div id="${fname}div">
  <input type="file" name="$name" size="30" id="${fname}file" />
  &nbsp;&nbsp;
  <input type="button" value="Input Text" id="${fname}input" style="color: blue" />
</div>
);
    
    my $content = qq(
<script type="text/javascript">
\$(document).ready( function() {
  ${fname}default();

  \$("#${fname}add").click( function() {
    var txt = \$("#${fname}value").val();
    if ( txt ) {
      \$("#${fname}sel").append('<option selected="selected" value="'+txt+'">'+txt+'</option>');
      \$("#${fname}value").val("");
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

1;
