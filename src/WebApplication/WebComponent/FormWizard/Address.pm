package WebComponent::FormWizard::Address;

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

    my $default = $question->{default} ? $question->{default} : '';
    $default    = (ref($default) && (ref($default) eq 'ARRAY')) ? $default->[0] : $default;
    my @value   = $default ? split(/ ; /, $default) : ('','','','');
    my $name    = $question->{name} || '';
    my $fname   = "Function" . $name;

    $fname =~ s/[\s_-]//g;

    my $IDstreet = $fname . "street";
    my $IDzip    = $fname . "zip";
    my $IDcity   = $fname . "city";
    my $IDstate  = $fname . "state";
    my $IDall    = $fname . "all";
  
    my $street  = "<input type='text' name='${name}_street' size='30' id='$IDstreet' value='$value[0]' onchange='$fname();' />";
    my $city    = "<input type='text' name='${name}_city'   size='30' id='$IDcity'   value='$value[2]' onchange='$fname();' />";
    my $zip     = "<input type='text' name='${name}_zip'    size='10' id='$IDzip'    value='$value[1]' onchange='$fname();' />";
    my $state   = "<input type='text' name='${name}_state'  size='10' id='$IDstate'  value='$value[3]' onchange='$fname();' />";

    my $content = qq~
<script>
function $fname () {
  var Street = document.getElementById("$IDstreet");
  var ZIP    = document.getElementById("$IDzip");
  var City   = document.getElementById("$IDcity");
  var State  = document.getElementById("$IDstate");
  var All    = document.getElementById("$IDall");
  All.value  = Street.value + " ; " + ZIP.value + " ; " + City.value + " ; " + State.value;
}
</script>
<table>
  <tr><td>Street:</td><td>$street</td></tr>
  <tr><td>City:</td><td>$city</td></tr>
  <tr><td>State:</td><td>$state</td></tr>
  <tr><td>Postal code:</td><td>$zip</td></tr>
</table>
<input type='hidden' name='$name' id='$IDall' value='$default' />
~;

    return $content;
}

1;
