package MGRAST::WebPage::Home;

use base qw( WebPage );

use strict;
use warnings;

use Conf;

1;

=pod

=head1 NAME

Home - an instance of WebPage which shows home information

=head1 DESCRIPTION

Display an home page

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my ($self) = @_;

  $self->title('Home');

  return 1;
}


=pod

=item * B<output> ()

Returns the html output of the Contact page.

=cut

sub output {
  my ($self) = @_;

  my $application = $self->application;
  my $user = $application->session->user;

  my $content = "<div id='info' style='display: none'></div>";
  my $is_old = $self->application->cgi->param('oldurl');
  if ($is_old) {
    $content .= qq~<script>
 function bookmark(url, title) {
   if (confirm('The URL you are using to reach this page is deprecated.\\nThe new URL is:\\n\\n\\t~.$Conf::cgi_url.qq~\\n\\nWould you like to bookmark the new location?')) {
     var url = url || location.protocol + '//' + location.host;
     var title = title || location.host;
     if(document.all) {
   	window.external.AddFavorite(url, title);
     } else if(window.sidebar) {
   	window.sidebar.addPanel(title, url, '');
     }
   }
   return false;
 }
 </script><img src='./Html/clear.gif' onload='bookmark("~.$Conf::cgi_url.qq~", "MG-RAST");'>~;
  }

  $content .= "<div class='clear' style='height:30px;'></div>";

  my $text_style ='font-size: 11pt; color: #8FBC3F; font-weight: bold; font-family: Verdana,Arial,sans-serif; margin:0px;float:left;';
  my $login_req = "<p style='color:#EA9D2F;float:left;font-size:16px;margin-bottom:0;margin-left:2px;margin-top:-2px;'>*</p>";

  $content .= '<script>
function forward_to_search (e) {
  if (e.keyCode == 13) {
    var stext  = document.getElementById("home_search").value;
    if (stext && stext.length) {
      if (stext.match(/^mgm\d+\.\d+$/)) {
        window.location = "?page=MetagenomeOverview&metagenome="+stext.substring(3);
      } else if (stext.match(/^\d+$/)) {
        window.location = "?page=MetagenomeProject&project="+stext;
      } else if (stext.match(/^\d{7}\.\d$/)) {
        window.location = "?page=MetagenomeOverview&metagenome="+stext;
      } else if (stext.match(/^mgp\d+$/)) {
        window.location = "?page=MetagenomeProject&project="+stext.substring(3);
      } else {
        window.location = "?page=MetagenomeSearch&init_search="+stext;
      }
    } else {
      alert("Please enter a search term");
    }
  }
}</script>';
  $content .= "<a title='Browse Metagenomes' href='?page=MetagenomeSelect'><img style='float: left; height: 30px; margin-bottom: 3px; margin-right: 7px;' src='./Html/mgrast_globe.png'><p style='".$text_style." margin-top: 4px;'>Browse Metagenomes</p></a><img onclick='event.keyCode = 13; forward_to_search(event);' style='cursor: pointer; float: right; height: 15px; margin-bottom: 3px; margin-top: 7px;' src='./Html/lupe.png'><input id='home_search' type='text' style='margin: 4px 4px 0px; float: right; color: gray; font-style: italic; font-size: 10px; width: 150px;' placeholder='search for metagenomes' onkeypress='forward_to_search(event);'><div class='clear'></div>";
  
  $text_style ='font-size: 11pt; color: #8FBC3F; font-weight: bold; font-family: Verdana,Arial,sans-serif;margin-top:6px;';
  my $image_style ="style='float:left; height: 30px;'";
  my $icon_style = "margin-right:20px;margin-left:35px;"; 


  my $about = "<p style='".$text_style."margin-bottom:0px;margin-right:10px;margin-left:5px;'>About</p>";
  my $register = "<img src='./Html/mg-register.png' ".$image_style."><p style='".$text_style.$icon_style."'>Register</p>";
  my $contact = "<img src='./Html/mg-contact.png' ".$image_style."><p style='".$text_style.$icon_style."'>Contact</p>";
  my $help = "<img src='./Html/mg-help.png' ".$image_style."><p style='".$text_style.$icon_style."'>Help</p>";
  my $upload = "<img src='./Html/mg-upload.png' ".$image_style."><p style='".$text_style."float:left;'>Upload</p>".$login_req;
  my $news = "<img src='./Html/mg-rss.png' style='margin-right:3px; margin-top:3px;float:left;'><p style='".$text_style."float:left;'>News</p>";

  $content .= "<div style='width:660px;'>";
  $content .= "<div style='margin-top:20px; float:left; cursor: pointer;margin-right:40px;padding-left:5px;padding-top:0px; background:white; -webkit-border-radius-topleft: 5px;-webkit-border-radius-topright: 5px;-moz-border-radius-topleft:5px;-moz-border-radius-topright:5px; border-top-left-radius: 5px; border-top-right-radius: 5;'>".$about."</div>";
  $content .= "<a href='?page=Register' title='Register a new account'><div style='float:left; cursor: pointer;padding-top:5px;'>".$register."</div></a>";  
  $content .= "<a href='?page=Contact' title='Click here for contact information'><div style='float:left; cursor: pointer;padding-top:5px;'>".$contact."</div></a>";
  $content .= "<a href='http://blog.metagenomics.anl.gov' title='Click here for support and FAQs'><div style='float:left; cursor: pointer;padding-top:5px;'>".$help."</div></a>";
  $content .= "<a href='./Html/mgmainv3.html?mgpage=upload' title='Upload a new metagenome'><div style='float:left; cursor: pointer;padding-top:5px; margin-right:20px;'>".$upload."</div></a>";
  $content .= "<a href='http://blog.metagenomics.anl.gov/' target=_blank><div style='float:left; cursor: pointer;padding-top:5px;'>".$news."</div></a>";
  $content .= "</div>";
  $content .= "<div class='clear'></div>";
  
  $content .= "<div style='background:white; width:650px; padding:10px;-webkit-border-radius-topright: 5px;-webkit-border-radius-bottomleft: 5px;-webkit-border-radius-bottomright: 5px;-moz-border-radius-bottomleft:5px;-moz-border-radius-bottomright:5px;-moz-border-radius-topright:5px; border-top-right-radius: 5px; border-bottom-right-radius: 5px; border-bottom-left-radius: 5px; color:#848484; font-size:14;'>";

  $content .= "<div style='margin: 5 0 0 10;'>MG-RAST (the Metagenomics RAST) server is an automated analysis platform for metagenomes providing quantitative insights into microbial populations based on sequence data.</div>";
  $content .= "<div class='clear'></div>";
  $content .= "<div style='background-color: #5281B0; border-radius: 5px; -webkit-border-radius: 5px; -moz-border-radius: 5px; color: white; padding: 6px 10px 10px 10px; float: left; width: 200px; height: 82px; margin-top: 10px;'>";
  $content .= "<div class='sidebar_subitem' style='font-size: 13px; margin-top:3px; padding: 1 0;'># of metagenomes<span class='sidebar_stat' style='font-size: 11px; padding-top:2px;' id='jobcount'></span></div>";
  $content .= "<div class='sidebar_subitem' style='font-size: 13px; padding: 1 0;'># base pairs<span class='sidebar_stat' style='font-size: 11px; padding-top:2px;' id='bpcount'></span></div>";
  $content .= "<div class='sidebar_subitem' style='font-size: 13px; padding: 1 0;'># of sequences<span class='sidebar_stat' style='font-size: 11px; padding-top:2px;' id='seqcount'></span></div>";
  $content .= "<div class='sidebar_subitem' style='font-size: 13px; padding: 1 0;'># of public metagenomes<span class='sidebar_stat' style='font-size: 11px; padding-top:2px;' id='publiccount'></span></div>";
  $content .= "</div>";
  $content .= "<div style='float: left; width: 410px; line-height: 17px; margin: 10 0 0 10;'>The server primarily provides upload, quality control, automated annotation and analysis for prokaryotic metagenomic shotgun samples. MG-RAST was launched in 2007 and has over 12,000 registered users and <span id='jobcount2'></span> data sets. The current server version is ".$Conf::server_version.". We suggest users take a look at <a href='http://blog.metagenomics.anl.gov/mg-rast-for-the-impatient'>MG-RAST for the impatient</a>. Also available for download is the <a href='ftp://ftp.metagenomics.anl.gov/data/manual/mg-rast-manual.pdf' target=_blank>MG-RAST manual</a>.</div>"; 

  $content .= "<div class='clear'></div>";
  $content .= qq~
    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
    <script type="text/javascript">
    
google.load("feeds", "1");

function initialize() {
    var feed = new google.feeds.Feed("http://press.igsb.anl.gov/mg-rast/feed/");
    feed.load(function(result) {
        if (!result.error) {
	    var html = "<ul style='position: relative; bottom: 6px; right: 22px;'>";
	    for (var i = 0; i < result.feed.entries.length; i++) {
		var entry = result.feed.entries[i];
		html += "<li><a href='"+entry.link+"' target=_blank>"+entry.title+"</a></li>";
	    }
	    html += "</ul>";
	    document.getElementById("newsfeed").innerHTML = html;
        }
    });
}

google.setOnLoadCallback(initialize);
    </script>
<script>
	Number.prototype.formatString = function(c, d, t) {
	    var n = this, c = isNaN(c = Math.abs(c)) ? 0 : c, d = d == undefined ? "." : d, t = t == undefined ? "," : t, s = n < 0 ? "-" : "", i = parseInt(n = Math.abs(+n || 0).toFixed(c)) + "", j = (j = i.length) > 3 ? j % 3 : 0;
	    return s + (j ? i.substr(0, j) + t : "") + i.substr(j).replace(/(\d{3})(?=\d)/g, "$1" + t) + (c ? d + Math.abs(n - i).toFixed(c).slice(2) : "");
	};
    // server status info
    jQuery.getJSON("http://api.metagenomics.anl.gov/server/MG-RAST", function (data) {
	// check if the server is down
	if (data.status != "ok") {
	    document.getElementById('info').innerHTML = data.info;
	    document.getElementById('info').style.display = "";
	}
	// check if there is an info message
	else if (data.info) {
	    document.getElementById('info').innerHTML = data.info;
	    document.getElementById('info').style.display = "";
	}
		
	// print server stats
	var bp = (parseInt(data.basepairs) / 1000000000000).formatString(2);
	var seq = parseInt(parseInt(data.sequences) / 1000000000).formatString();

	document.getElementById('bpcount').innerHTML = bp + " Tbp";
	document.getElementById('seqcount').innerHTML = seq + " billion";
	document.getElementById('jobcount').innerHTML = parseInt(data.metagenomes).formatString();
        document.getElementById('jobcount2').innerHTML = parseInt(data.metagenomes).formatString();
	document.getElementById('publiccount').innerHTML = parseInt(data.public_metagenomes).formatString();
    });
</script>
~;
  $content .= "<div id='newsfeed' style='margin-top: 15px; height: 70px;'></div>";
  $content .= "</div>";

  $content .= "<p style='color:#EA9D2F;text-align:right;font-size:12px;margin-top:3px;'>* login required</p>";

  $content .= "<p style='color:#8FBC3F;text-align:left;font-size:9px;margin-top:3px;'>This project has been funded in part with Federal funds from the National Institute of Allergy and Infectious Diseases under Contract No. R01AI123037.</p>";

  $content .= "<p style='color:#8FBC3F;text-align:left;font-size:9px;margin-top:3px;'>This work was supported in part by the National Institute of Allergy and Infectious Diseases, National Institutes of Health, Department of Health and Human Services, under Contract No. HHSN272200900040C and the Office of Advanced Scientific Computing Research, Office of Science, U.S. Department of Energy, under Contract DE-AC02-06CH11357.</p>";

  $content .= "<a href=\"http://www.biomedcentral.com/1471-2105/9/386\" target=\"_blank\"><p style='border-radius: 5px; -webkit-border-radius: 5px; -moz-border-radius: 5px; color: white; padding: 5px 0px 3px 10px; color: white; font-size:14; background-color: #5281B0; width: 100px; float: left; margin-right: 10px; top: -12px; position: relative;'>cite MG-RAST</p></a><a href=\"http://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1004008\" target=\"_blank\" style=\"float: right;\"><p style='border-radius: 5px; -webkit-border-radius: 5px; -moz-border-radius: 5px; color: white; padding: 5px 0px 3px 10px; color: white; font-size:14; background-color: #5281B0; width: 120px; float: left; margin-right: 10px; top: -12px; position: relative;'>cite MG-RAST API</p></a>";

  my $logos = "<img src='./Html/argonne_header_logo.jpg' style='padding-top: 15px; width: 150px;'>";

  return $content;
}

sub speedometer {
  my ($self) = @_;

  my $content = "";

  if (open(FH, $Conf::mgrast_jobs."/statistics_short")) {
    my $line = <FH>;
    close FH;
    my ($speed, $mileage, $trip, $togo) = split(/\t/, $line);

    $content .= "<table style='background-color: #2f2f2f; position: absolute; right: 22px; top: 78px; color: rgb(143, 188, 63); font-family: Verdana,Arial,sans-serif;'><tr><td colspan=3 align=center style='font-size: 9pt;font-weight: bold;'>pipeline status</td></tr><tr title='analysis speed in basepairs/second'><td align=right style='font-size: 8pt;'>$speed</td><td align=left style='font-size: 8pt;'>bp/s</td><td align=left style='font-size: 8pt;'>speed</td></tr><tr title='data analyzed in the last 30 days'><td align=right style='font-size: 8pt;'>$trip</td><td align=left style='font-size: 8pt;'>Mbp</td><td align=left style='font-size: 8pt;'>last 30 days</td></tr><tr title='data left to be processed'><td align=right style='font-size: 8pt;'>$togo</td><td align=left style='font-size: 8pt;'>Mbp</td><td align=left style='font-size: 8pt;'>in queue</td></tr><tr title='total amount of data analyzed'><td align=right style='font-size: 8pt;'>$mileage</td><td align=left style='font-size: 8pt;'>Mbp</td><td align=left style='font-size: 8pt;'>total</td></tr></table>";
  }

  return $content;
}

