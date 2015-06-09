package StreamingUpload;

use strict;
use warnings;
our $VERSION = '0.01';

use Carp ();
use HTTP::Request;

sub new {
    my($class, $method, $uri, %args) = @_;

    my $headers = $args{headers};
    if ($headers) {
        if (ref $headers eq 'HASH') {
            $headers = +[ %{ $headers } ];
        }
    }
    
    my $req = HTTP::Request->new($method, $uri, $headers);
    _set_content($req, \%args);
    $req;
}

sub _set_content {
    my($req, $args) = @_;

    if ($args->{content}) {
        $req->content($args->{content});
    } elsif ($args->{callback} && ref($args->{callback}) eq 'CODE') {
        $req->content($args->{callback});
    } elsif ($args->{path} || $args->{fh}) {
        my $fh;
        if ($args->{fh}) {
            $fh = $args->{fh};
        } else {
            open $fh, '<', $args->{path} or Carp::croak "$args->{path}: $!";
        }
        my $chunk_size = $args->{chunk_size} || 4096;
        $req->content(sub {
            my $len = read($fh, my $buf, $chunk_size);
            return unless $len;
            return $buf;
        });
    }
}

sub slurp {
    my(undef, $req) = @_;
    my $content_ref = $req->content_ref;
    $content_ref = ${ $content_ref } if ref ${ $content_ref };

    my $content;
    if (ref($content_ref) eq 'CODE') {
        while (1) {
            my $buf = $content_ref->();
            last unless defined $buf;
            $content .= $buf;
        }
    } else {
        $content = ${ $content_ref };
    }
    $content;
}

1;
