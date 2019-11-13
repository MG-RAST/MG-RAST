package MGRAST::Mailer;

use strict;
use warnings;

use Net::SMTP;
use POSIX qw(strftime);
use Encode qw(encode_utf8);

1;

=item send_email

Send email using the Smarthost configured in Config.

$from
$to
$body
$subject

are arguments.

=cut
sub send_email {
    my (%args) = @_;

    # we read the smart_host config directly from Config file
    while (my ($k, $v) = each %args) { $args{$k} = encode_utf8($v); }
    my $smtp_host = $Conf::smtp_host,

    my $from = $args{'from'};
    my $to = $args{'to'};

    my $subject = $args{'subject'};
    my $body = $args{'body'};


    #my $smtp = Net::SMTP->new($Conf::smtp_host, Hello => $Conf::smtp_host);
    my $smtp = Net::SMTP->new($smtp_host, Hello => $smtp_host);

    unless (defined $smtp) {
        print("\$smtp is undefined (smtp_host: $smtp_host)");
        return 0;
    }

    my @data = (
        "To: $to\n",
        "From: $from\n",
        "Date: ".strftime("%a, %d %b %Y %H:%M:%S %z", localtime)."\n",
        "Subject: $subject\n\n",
        $body
    );

    $smtp->mail("$from");
    if ($smtp->to($to)) {
        $smtp->data(@data);
    }
    $smtp->quit;
    return 1;
}
