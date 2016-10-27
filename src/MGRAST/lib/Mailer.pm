package MGRAST::Mailer;

use strict;
use warnings;

use Net::SMTP;
use POSIX qw(strftime);

1;

sub send_email {
    my (%args) = @_;
    
    
    my $smtp_host = $args{'smtp_host'};
    
    my $from = $args{'from'};
    my $to = $args{'to'};
    
    my $subject = $args{'subject'};
    my $body = $args{'body'};
    
    
    #my $smtp = Net::SMTP->new($Conf::smtp_host, Hello => $Conf::smtp_host);
    my $smtp = Net::SMTP->new($smtp_host, Hello => $smtp_host);
    
    my @data = (
        "To: $to\n",
        "From: $from\n",
        "Date: ".strftime("%a, %d %b %Y %H:%M:%S %z", localtime)."\n",
        "Subject: $subject\n\n",
        $body
    );
    
    $smtp->mail('mg-rast');
    if ($smtp->to($to)) {
        $smtp->data(@data);
    } 
    $smtp->quit;
    return 1;
}
