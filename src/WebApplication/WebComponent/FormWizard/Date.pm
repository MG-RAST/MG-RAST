package WebComponent::FormWizard::Date;

use strict;
use warnings;

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

    my $default = $question->{default} ? $question->{default} : "yyyymmdd";
    $default    = (ref($default) && (ref($default) eq 'ARRAY')) ? $default->[0] : $default;
    my $name    = $question->{name} || '';
    my $fname   = "Function" . $name;

    $fname =~ s/[\s_-]//;

    my $IDyear  = $fname."year";
    my $IDmonth = $fname."month";
    my $IDday   = $fname."day";
    my $IDall   = $fname."all";

    my $scripts = qq~
<script>
function $fname () {
 var Year  =  document.getElementById("$IDyear");
 var Month =  document.getElementById("$IDmonth");
 var Day   =  document.getElementById("$IDday")
 var All   =  document.getElementById("$IDall");
 All.value = Year.value + Month.value + Day.value ; 

 if (Year.value.length !== 4 ){
  alert( "Year is not a 4 digit number, e.g. 2009");
 }
 if (Month.value.length !== 2 ){
  alert( "Month has to be  a 2 digit number , e.g. 06 for June");
 }
 if (Day.value.length !== 2 ){
  alert( "Day has to be 2 digit number, e.g. 01 or 12");
 }
}
</script>~; 

    my ($y,$m,$d) = ('yyyy', 'mm', 'dd');
    if ( $default =~/(....)(..)(..)/ ) {
      ($y,$m,$d) = ($1, $2, $3);
    }

    my $content .= $scripts;
    $content .= "<input type='text' size='4' maxlength='4' name='${name}_year' id='$IDyear' value='$y' onchange='$fname();'>";
    $content .= " - <input type='text' size='2' maxlength='2' name='${name}_month' id='$IDmonth' value='$m' onchange='$fname();'>";
    $content .= " - <input type='text' size='2' maxlength='2' name='${name}_day' id='$IDday' value='$d' onchange='$fname();'>";
    $content .= "<input type='hidden' name='$name' id='$IDall' value='$default'>";
    return $content;
}

sub get_time {
    my ($self, $format) = @_;

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
