package resources2::pcoa;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources2::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->{user} ? map {$_, 1} @{$self->{user}->has_right_to(undef, 'view', 'metagenome')} : ();
    $self->{name} = "pcoa";
    $self->{rights} = \%rights;
    $self->{attributes} = { "data" => [ 'object', 'return data' ],
                          };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "Calculate a PCoA for given input data.",
		    'type' => 'object',
		    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				      'request'     => $self->cgi->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options'     => {},
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->cgi->url."/".$self->name."/calc",				      
				      'description' => "Returns the calculated data.",
				      'method'      => "GET" ,
				      'type'        => "synchronous",
				      'attributes'  => $self->{attributes},
				      'parameters'  => { 'options'  => {},
							 'required' => {},
							 'body'     => { 'data' => [ "array", "array of input data" ] } } },
				     ]
				 };

    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # prepare data
    use CGI;
    my $cgi = new CGI;
    my $data = $self->prepare_data(join("", $cgi->param('keywords')));

    $self->return_data($data)
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;

    use JSON;
    my $json = JSON->new();
    my $perldata = $json->decode($data);

    use File::Temp qw/ tempfile tempdir /;
    
    # write data to a tempfile
    my ($fh, $infile) = tempfile( "rdataXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
    foreach my $row (@$perldata) {
      print $fh join("\t", @$row)."\n";
    }
    close $fh;
    chmod 0666, $infile;
    
    # preprocess data
    my $time = time;
    my ($prefh, $prefn) =  tempfile( "rpreprocessXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
    print $prefh "source(\"".$Conf::bin."/preprocessing.r\")\n";
    print $prefh "MGRAST_preprocessing(file_in = \"".$infile."\", file_out = \"".$Conf::temp."/rdata.preprocessed.$time\", produce_fig = \"FALSE\")\n";
    close $prefh;
    
    my $R = ($Conf::r_executable) ? $Conf::r_executable : "R";
    `$R --vanilla --slave < $prefn`;
    unlink($prefn);
    
    unlink $infile;
    $infile = $Conf::temp."/rdata.preprocessed.$time";
    
    $time = time;
    my ($pca_data) = ($Conf::temp."/rdata.pca.$time");
    my ($pcah, $pcan) =  tempfile( "rpcaXXXXXXX", DIR => $Conf::temp, SUFFIX => '.txt');
    print $pcah "source(\"".$Conf::bin."/plot_pco.r\")\n";
    print $pcah "MGRAST_plot_pco(file_in = \"".$infile."\", file_out = \"".$pca_data."\", dist_method = \"bray-curtis\", headers = 0)\n";
    close $pcah;
    `$R --vanilla --slave < $pcan`; 
    unlink($pcan);
    
    my $retval = "";
    open(FH, "<$pca_data") or die "oh noes: $@\n";
    while (<FH>) {
      $retval .= $_;
    }
    close FH;
    unlink($pca_data);
    
    return $retval;
}

1;
