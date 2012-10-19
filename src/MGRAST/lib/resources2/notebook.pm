package resources2::notebook;

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
    $self->{name}       = "notebook";
    $self->{attributes} = { "id"       => [ 'string', 'unique shock identifier' ],
                            "name"     => [ 'string', 'human readable identifier' ],
                            "uuid"     => [ 'string', 'ipynb identifier - stable across different versions'],
                            "notebook" => [ 'hash', 'notebook object in JSON format' ],
                            "created"  => [ 'date', 'time the object was first created' ],
                            "version"  => [ 'integer', 'version of the object' ],
                            "url"      => [ 'uri', 'resource location of this object instance' ]
                          };
    return $self;
}


# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name'          => $self->name,
                    'url'           => $self->cgi->url."/".$self->name,
                    'description'   => "A metagenome is an analyzed set sequences from a sample of some environment",
                    'type'          => 'object',
                    'documentation' => '',
                    'requests'      => [],
                  };
    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # get data
    my $id   = $self->rest->[0];
    my $node = $self->get_shock_node($id);
    unless ($node) {
        $self->return_data( {"ERROR" => "id $id does not exists"}, 404 );
    }

    # check rights
    my $uname = $self->user ? $self->user->login : '';
    unless (($node->{attributes}{user} eq 'public') || ($node->{attributes}{user} eq $uname)) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # prepare data
    my $data = $self->prepare_data( [$node] );
    $data = $data->[0];

    $self->return_data($data);
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;
 
    # get all items the user has access to
    my $uname = $self->user ? $self->user->login : '';
    my $nodes = [];
    map { push @$nodes, $_ } @{ $self->get_shock_query( {type => 'ipynb', user => $uname} ) };
    map { push @$nodes, $_ } @{ $self->get_shock_query( {type => 'ipynb', user => 'public'} ) };
    my $total = scalar @$nodes;
 
    # check limit
    my $limit  = $self->cgi->param('limit')  || 10;
    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order')  || "id";
    @$nodes = sort { $a->{$order} cmp $b->{$order} } @$nodes;
    @$nodes = @$nodes[$offset..($offset+$limit-1)];
 
    # prepare data to the correct output format
    my $data = $self->prepare_data($nodes);

    # check for pagination
    $data = $self->check_pagination($data, $total);

    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
    my ($self, $data) = @_;
    
    my $objects = [];
    foreach my $node (@$data) {
        my $url = $self->cgi->url;
        my $obj = {};
        $obj->{id}       = $node->{id};
        $obj->{name}     = $node->{attributes}{name};
        $obj->{uuid}     = $node->{attributes}{uuid};
        $obj->{created}  = $node->{attributes}{created};
        $obj->{version}  = 1;
        $obj->{url}      = $url.'/notebook/'.$obj->{id};
        if ($self->cgi->param('verbosity') && ($self->cgi->param('verbosity') eq 'full')) {
            $obj->{notebook} = $self->json->decode( $self->get_shock_file($obj->{id}) );
        }
        push @$objects, $obj;
    }
    return $objects;
}

1;