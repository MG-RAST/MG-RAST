package resources::user_inbox;

use CGI;
use JSON;

my $cgi = new CGI;
my $json = new JSON;
$json = $json->utf8();

sub about {
  my $content = { 'description' => "shows the contents of, deletes and unpacks files in a user inbox",
		  'parameters' => { "id" => "string" },
		  'return_type' => "application/x-download" };

  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode($content);
  exit 0;
}

sub request {
  my ($params) = @_;

  my $rest = $params->{rest_parameters};

  my $user = $params->{user};

  if ($rest && scalar(@$rest) == 1 && $rest->[0] eq 'about') {
    &about();
    exit 0;
  }

  unless ($user) {
    print $cgi->header(-type => 'text/plain',
		       -status => 401,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Invalid authentication for user_inbox call";
    exit 0;
  }

  use Digest::MD5 qw(md5_base64);
  my $basedir = "/homes/paczian/public/upload_test/";
  my $dir = $basedir.md5_base64($user->login)."/";
 
  if (scalar(@$rest)) {
    my $action = shift @$rest;
    if ($action eq 'del') {
      foreach my $file (@$rest) {
	if (-f "$dir$file") {
	  `rm $dir$file`;
	}
      }
    }

    if ($action eq 'unpack') {
      foreach my $file (@$rest) {
	if (-f "$dir$file") {
	  if ($file =~ /\.tar\.gz$/) {
	    `tar -xzf $dir$file -C $dir`;
	  } elsif ($file =~ /\.(gz|zip)$/) {
	    `unzip -d $dir $dir$file`;
	  }
	}
      }
    } 
  }

  my $data = [ { type => 'user_inbox', id => $user->login, files => [] }];
  if (opendir(my $dh, $dir)) {
    my @ufiles = grep { /^[^\.]/ && -f "$dir/$_" } readdir($dh);
    closedir $dh;
    
    foreach my $ufile (@ufiles) {
      push(@{$data->[0]->{files}}, $ufile);
    }
  } else {
    print $cgi->header(-type => 'text/plain',
		       -status => 500,
		       -Access_Control_Allow_Origin => '*' );
    print "ERROR: Could not access inbox directory";
    exit 0;
  }

  @{$data->[0]->{files}} = sort { lc $a cmp lc $b } @{$data->[0]->{files}};
  
  print $cgi->header(-type => 'application/json',
		     -status => 200,
		     -Access_Control_Allow_Origin => '*' );
  print $json->encode( $data );
}

sub TO_JSON { return { %{ shift() } }; }

1;
