package MGRAST::MyAppRights;

1;

use strict;
use warnings;

sub rights {
	return [ [ 'login','*','*' ], [ 'view','registration_mail','*' ], ];
}
