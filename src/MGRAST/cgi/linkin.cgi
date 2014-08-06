use strict;
use warnings;
no warnings 'once';

use WebApplication;
use WebMenu;
use WebLayout;
use WebConfig;

use Conf;

eval {
    &main;
};

if ($@)
{
    my $cgi = new CGI();

    print $cgi->header(-charset => 'UTF-8');
    print $cgi->start_html();
    
    # print out the error
    print '<pre>'.$@.'</pre>';

    print $cgi->end_html();

}

sub main {
    my  $cgi = new CGI();

    my $error = -1;
    if ($cgi->param('metagenome')) {
	
	if ($cgi->param('metagenome') =~ /^(mgm)?(\d+\.\d+)$/) {
	    print $cgi->redirect('metagenomics.cgi?page=MetagenomeOverview&metagenome='.$2);
	} else {
	    $error = '<h2>Invalid link</h2><p>You linked to MG-RAST using an invalid id format: '.$cgi->param('metagenome').'<br>Valid ids for metagenomes are of the format 12345.6 or mgm12345.6.</p>';
	}
    } elsif ($cgi->param('project')) {
	if ($cgi->param('project') =~ /^(mgp)?(\d+)$/) {
	    print $cgi->redirect('metagenomics.cgi?page=MetagenomeProject&project='.$2);
	} else {
	    $error = '<h2>Invalid link</h2><p>You linked to MG-RAST using an invalid id format: '.$cgi->param('project').'<br>Valid ids for projects are of the format 123 or mgp123.</p>';
	}
    
    } else {
	my @params = $cgi->keywords;
	foreach my $p (@params) {
	    if ($p =~ /^project(\d+)$/) {
		print $cgi->redirect('metagenomics.cgi?page=MetagenomeProject&project='.$1);
	    }
	}
	
	$error = '<h2>Invalid link</h2><p>You linked to MG-RAST without passing an appropriate id.<br></p>';
    }

    if ($error) {
	print $cgi->header(-charset => 'UTF-8');
	print $cgi->start_html(-title => 'MG-RAST linkin');
	
	# print out the error
	print $error;

	print "<p>For detailed information on how to link to MG-RAST please refer to <a href='http://blog.metagenomics.anl.gov/howto/link-to-mg-rast/'>our FAQ</a></p>";
	
	print $cgi->end_html();
    }
}
