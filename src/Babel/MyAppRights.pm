package Babel::MyAppRights;

1;

use strict;
use warnings;

sub rights {
	return [ [ 'view','registration_mail','*' ], [ 'view','group_request_mail','*' ], [ 'login','*','*' ], [ 'view','user','*' ], [ 'add','user','*' ], [ 'delete','user','*' ], [ 'edit','user','*' ], [ 'view','scope','*' ], [ 'add','scope','*' ], [ 'delete','scope','*' ], [ 'edit','scope','*' ], ];
}
