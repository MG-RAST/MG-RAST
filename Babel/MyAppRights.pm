package Babel::MyAppRights;

1;

use strict;
use warnings;

sub rights {
	return [ [ 'login','*','*' ], [ 'view','user','*' ], [ 'add','user','*' ], [ 'delete','user','*' ], [ 'edit','user','*' ], [ 'view','scope','*' ], [ 'add','scope','*' ], [ 'delete','scope','*' ], [ 'edit','scope','*' ], [ 'view','group_request_mail','*' ], [ 'view','registration_mail','*' ], ];
}
