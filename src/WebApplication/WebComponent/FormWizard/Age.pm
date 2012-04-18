package WebComponent::FormWizard::Age;

use strict;
use warnings;

sub new{
    my ($class , $wizard , $question , $value) = @_;
    my $self = { question => $question ,
		 value    => $value || '' ,
		 wizard   => $wizard,
	     };

    bless $self;

    return $self;
}

sub question{
    my ($self,$question) = @_;

    if ($question and ref $question){
	$self->{question} = $question
    }

    return $self->{question};
}

sub wizard{
    my ($self,$wizard) = @_;

    if ($wizard and ref $wizard){
        $self->{wizard} = $wizard
	}

    return $self->{wizard};
}

sub value{
    my ($self,$value) = @_;

    if ($value){
        $self->{value} = $value
	}

    return $self->{value};
}

sub output {
    my ($self , $question , $value) = @_;
    my $name = $question->{name} || $self->question->{ name };

    my $fname = $name;
    $fname =~ s/\s|_|-//g;
    my $IDyear  = $fname."year";
    my $IDmonth  = $fname."month";
    my $IDday  = $fname."day";
    my $IDhour  = $fname."hour";
    my $IDminute = $fname."minute";
    my $IDsecond   = $fname."second";
    my $IDall   = $fname."all";

    my $scripts = "<script>\n";
    $scripts .= qq~ 
function $fname () {
 var Year     =  document.getElementById("$IDyear");
 var Month    =  document.getElementById("$IDmonth");
 var Day      =  document.getElementById("$IDday");
 var Hour     =  document.getElementById("$IDhour");
 var Minute   =  document.getElementById("$IDminute");
 var Second   =  document.getElementById("$IDsecond");
 
 var All   =  document.getElementById("$IDall");
 var tmp = Year.value + "/" + Month.value + "/" + Day.value + "/" + Hour.value + "/" + Minute.value + "/" + Second.value ; 
 All.value = tmp ;

 if (Hour.value.length !== 2 ){
  alert( "Hour is not a 2 digit number, e.g. 14 for 2 PM");
 }
 if (Minute.value.length !== 2 ){
  alert( "Minutes have to be  a 2 digit number , e.g. 03");
 }
 if (Second.value.length !== 2 ){
  alert( "Seconds have to be 2 digit number, e.g. 01 or 12");
 }
 if (Hour.value > 24) {
  alert( "Please use numbers between 00 and 24 for hour.");
 }
if (Minute.value > 59) {
  alert( "Please use numbers between 00 and 59 for minutes.");
 }
if (Second.value > 59) {
  alert( "Please use numbers between 00 and 59 for seconds.");
 }

}~; 

   
    my $default =  $self->question->{default} || "";
    my ($y,$mo,$d,$h,$m,$s) = ('years','months','days','hh','mm','ss');
    ($y,$mo,$d,$h,$m,$s) = split ("/" , $default) if ($default);
 
    $y  = "-" unless ($y) ;
    $mo = "-" unless ($mo);
    $d  = "-" unless ($d) ;
    $h  = "-" unless ($h) ;
    $m  = "-" unless ($m) ;
    $s  = "-" unless ($s) ; 

    $scripts .= "</script>\n";
    my $content .= $scripts;
    $content .= "<table>";
    $content .= "<tr><td>Years</td><td>"."<input type='text' size='4' name='".$fname."_year'   id='$IDyear'  value='$y'  onchange='$fname();'>"."</td></tr>";
    $content .= "<tr><td>Months</td><td>"."<input type='text' size='4' name='".$fname."_month'   id='$IDmonth'  value='$mo'  onchange='$fname();'>"."</td></tr>";
    $content .= "<tr><td>Days</td><td>"."<input type='text' size='4' name='".$fname."_day'   id='$IDday'  value='$d'  onchange='$fname();'>"."</td></tr>";
    $content .= "<tr><td>Hours</td><td>"."<input type='text' size='4' maxlength='2' name='".$fname."_hour'   id='$IDhour'  value='$h'  onchange='$fname();'>";
    $content .= "<tr><td>Minutes</td><td>"."<input type='text' align='right' size='4' maxlength='2' name='".$fname."_minute' id='$IDminute' value='$m'    onchange='$fname();'>"."</td></tr>";
    $content .= "<tr><td>Seconds</td><td>"."<input type='text' size='2' maxlength='4' name='".$fname."_second'   id='$IDsecond'   value='$s'    onchange='$fname();'>"."</td></tr>";
    $content .= "</table>";
    $content .= "<input type='hidden' name='$name' id='$IDall' value='$default'>";
    return $content;
}


sub get_time{
    my ( $self ,  $format ) = @_;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    my $version = 0;

    $mon++;
    $year += 1900;

    $mday = "0".$mday if ( $mday < 10 );
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
