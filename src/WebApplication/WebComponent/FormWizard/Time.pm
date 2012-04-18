package WebComponent::FormWizard::Time;

use strict;
use warnings;

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
  my ($self, $value) = @_;

  if (ref($value) eq 'ARRAY') { $value = $value->[0]; }
  if ($value eq 'hhmmss')     { return []; }

  $value =~ s/hh/00/;
  $value =~ s/mm/00/;
  $value =~ s/ss/00/;

  return ($value =~ /^\d{6}$/) ? [$value] : undef;
}

sub unencode_value {
  my ($self, $value) = @_;
  
  if ($value =~ /^(\d\d)(\d\d)(\d\d)$/) {
    return $1.":".$2.":".$3;
  }
  return $value;
}

sub output {
    my ($self, $question, $value) = @_;

    $question = ($question && ref($question)) ? $question : $self->question;

    my $default = $question->{default} ? $question->{default} : "hhmmss";
    $default    = (ref($default) eq 'ARRAY') ? (@$default ? $default->[0] : "hhmmss") : $default;
    my $name    = $question->{name} || '';
    my $fname   = $name;

    $fname =~ s/\s|_|-//g;

    my $IDhour   = $fname."hour";
    my $IDminute = $fname."minute";
    my $IDsecond = $fname."second";
    my $IDall    = $fname."all";
    my $scripts  = qq~
<script>
function $fname () {
  var Hour   =  document.getElementById("$IDhour");
  var Minute =  document.getElementById("$IDminute");
  var Second =  document.getElementById("$IDsecond");
  var All    =  document.getElementById("$IDall");
  All.value  = Hour.value + Minute.value + Second.value ; 

  if (Hour.value.length !== 2 ) {
    alert("Hour is not a 2 digit number, e.g. 14 for 2 PM");
  }
  if (Minute.value.length !== 2 ) {
    alert("Minutes have to be  a 2 digit number , e.g. 03");
  }
  if (Second.value.length !== 2 ) {
    alert("Seconds have to be 2 digit number, e.g. 01 or 12");
  }
  if (Hour.value > 24) {
    alert("Please use numbers between 00 and 24 for hour.");
  }
  if (Minute.value > 59) {
    alert("Please use numbers between 00 and 59 for minutes.");
  }
  if (Second.value > 59) {
    alert("Please use numbers between 00 and 59 for seconds.");
  }
}
</script>~; 

    my ($h,$m,$s) = ('hh', 'mm', 'ss');
    if ( $default =~ /(\d\d)(\d\d)(\d\d)/ ) {
      ($h,$m,$s) = ($1, $2, $3);
    }

    my $content .= $scripts;
    $content .= "<input type='text' size='4' maxlength='2' name='${name}_hour' id='$IDhour' value='$h' onchange='$fname();'>";
    $content .= " : <input type='text' align='right' size='2' maxlength='2' name='${name}_minute' id='$IDminute' value='$m' onchange='$fname();'>";
    $content .= " : <input type='text' size='2' maxlength='2' name='${name}_second' id='$IDsecond' value='$s' onchange='$fname();'>";
    $content .= "<input type='hidden' name='$name' id='$IDall' value='$default'>";
    return $content;
}


sub get_time{
    my ( $self ,  $format ) = @_;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    my $version = 0;

    $mon++;
    $year += 1900;

    $mday = "0".$mday if ($mday < 10);
    $min  = "0".$min if ($min < 10);
    $sec  = "0".$sec if ($sec < 10);
    $mon  = "0".$mon if ($mon < 10);

    my $time = "$hour:$min:$sec $mday.$mon.$year";

    if ($format) {
	if ( $format eq "l" ){
	    $time = "$hour:$min $mday.$mon.$year";
	}
	elsif( $format eq "YYYY" ){
	    $time = $year;
	}
	elsif( $format eq "MM" ){
	    $time = $mon;
	}
	elsif( $format eq "DD" ){
	    $time = $mday;
	}
	elsif( $format eq "hh" ){
	    $time = $hour;
	}
	elsif( $format eq "mm" ){
	    $time = $min;
	}
	elsif( $format eq "ss" ){
	    $time = $min;
	}
	else{
	    $time = "$hour:$min:$sec $mday.$mon.$year";
	}
    }

return $time
}



1;
