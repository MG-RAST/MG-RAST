package WebComponent::Comments;
#
#===============================================================================
#
#         FILE:  Comments.pm
#
#  DESCRIPTION:  Access to the commenting system
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  Now implementing PPO.
#       AUTHOR:  Scott Devoid (devoid@uchicago.edu) 
#      COMPANY:  University of Chicago, Argonne
#      VERSION:  0.5
#      CREATED:  06/23/09 14:54:10
#     REVISION:  ---
#===============================================================================

#use strict;
use warnings;
use URI::Escape;
use DBMaster;
use base qw( WebComponent );

use FIGMODEL;
use Conf;
1;
$DEBUG = 1;
=pod
=head1 NAME
Comments
=head1 DESCRIPTION
View, Add, Edit, Remove comments from the commenting system.
=head1 PUBLIC METHODS
=over 4
=item * B<new> ()
Called when the object is initialized. Expands SUPER::new.
=cut
sub new {
	my $self = shift->SUPER::new(@_);
	my $dbMaster = DBMaster->new(-database => 'WebComments',
		-host => $Conf::webapplication_host,
		-user => $Conf::webapplication_user, -backend => 'MySQL');
	$self->{'db'} = $dbMaster; 
	return $self;
}



sub title {
	my ($self, $title) = @_;
	if(defined($title)) { $self->{'title'} = $title; }
	return $self->{'title'};
}

sub sortOrder {
	my ($self, $sortOrder) = @_;
	if(defined($sortOrder)) { $self->{'sortOrder'} = $sortOrder; }
	return $self->{'sortOrder'};
}

sub width {
	my ($self, $width) = @_;
	if(defined($width)) { $self->{'width'} = $width; }
	return $self->{'title'};
}
	
sub ajax {
	my ($self, $ajaxComponent) = @_;
	if(defined($ajaxComponent)) { $self->{'ajax'} = $ajaxComponent; }
	return $self->{'ajax'};
}

sub _set_defaults {
	my ($self) = @_;
	$self->title($self->{'title'} || 'Comments');
	$self->sortOrder($self->{'sortOrder'} || 'oldestToNewest');
	$self->width($self->{'width'} || 600);
}

sub output {
	my ($self, $ID) = @_;
	my $output;
	$self->_set_defaults();
	unless(defined($ID)) {
		$self->application()->add_message('warning',
			"The conversation specified does not exist.");
	}
	unless(defined($self->ajax())) { 
		$self->application()->add_message('warning',
			"Missing Ajax backend.");
	}
	return $self->DisplayConversation($ID);
}	

=item * B<add> ()
Takes: 	$ID			the reference to the comment element
		$COMNUM		the comment number to edit (-1 if SINGLE COMMENT system,
												-2 if it is a new comment,
												otherwise the comment number (0..))
		$COMMENT	 the comment string
		$DISPLAYTYPE how to format the returned view and stores comment.
=cut
sub add {
	my ($self) = @_;
	my $cgi = $self->application()->cgi();
	my $ID = $cgi->param('id');
	my $COMNUM = $cgi->param('comnum');
	my $COMMENT = $cgi->param('comment');
	unless(defined($ID) && defined($COMNUM) && defined($COMMENT)) { 
		return $self->DisplayError("There was an error in saving your comment."); }
	my $DATE = _timestamp();
	my $USER = $self->application()->session()->user();
	unless(defined($USER)) { 
		return $self->DisplayError("You must be logged in to comment.");
	}
	my $commentHash = { ReferenceObject => $ID, _id => $COMNUM, Text => $COMMENT,
		Date => $DATE, User => $USER, Cgi => $cgi };
	my @ErrorStrings;	
	my $CommentObj; # Now set the comment. Return error on failure.
	unless(defined($CommentObj = $self->setComment($commentHash))) {
		 return $self->DisplayError("There was an error in saving your comment.");
	}
	return $self->DisplayCommentContents($CommentObj);
}


=item * B<edit> ()
Takes: 	$ID			the reference to the comment element
		$COMNUM		the comment number to edit (-1 if SINGLE COMMENT system,
	-2 if it is a new comment, otherwise the comment number (0..))
		$COMMENT	the comment string
		$DISPLAYTYPE	how to format the returned view 
	and returns a view to edit that comment; privileges are
	handled on comment addtion (but views should present users
	with edit fields only when they SHOULD have edit permissions).
=cut
sub edit {
	my ($self) = @_;
	my $cgi = $self->application()->cgi();
	my $ID = $cgi->param('conv');
	my $COMNUM = $cgi->param('comnum');
#	my $DISPLAYTYPE = $cgi->param('display');
	unless(defined($ID) && defined($COMNUM)) {
		return $self->DisplayError("Unable to edit this comment at this time.");
	}
	return $self->DisplayEdit($ID, $COMNUM);
}

sub cancel {
	my ($self) = @_;
	my $cgi = $self->application()->cgi();
	my $ID = $cgi->param('id');
	my $COMNUM = $cgi->param('comnum');
	my $oldComment = $self->getCommentById($ID, $COMNUM);
	if(defined($oldComment)) { return $self->DisplayCommentContents($oldComment);}
	else { return $self->DisplayError("Comment not found.");}
}

### Add/Edit Permission Methods ###
=item * B<canEdit> ()
Returns 1 if the login user has edit permissions on
the specified comment. Otherwise, returns 0.
=cut
sub canEdit {
	my ($self, $CommentObj) = @_;
	my $UserObj = $self->application()->session()->user();
	# The user must be logged in to edit or post.
	unless(defined($UserObj)) { return 0; }
	# Now if the User is an Admin, allow them to edit the comment
    my $admin_access = $UserObj->has_right($self->application(), 'edit', 'user', '*');
	if($admin_access) { return 1; }
	# If no comment is passed, post permission is allowed for all logged in users.
	unless(defined($CommentObj)) { return 1; }
	# If current user owns Comment Object, they can edit.
	my $CommentOwner = $CommentObj->User()->login();
	if( $CommentOwner eq $UserObj->login() ) { return 1; }
	else { return 0; }
}

### Display Methods ###
=item * B<DisplayEdit> ()
Takes: $ID, $COMNUM, $COMMENT
=cut
sub DisplayEdit {
	my ($self, $ID, $COMNUM) = @_;
	my $componentID = $self->{_id};
    my $COMMENT;
	my $outstr;
	if(defined($COMNUM) && $COMNUM eq '-2') {
		$COMMENT = "";
	} else { 
		my $Comment = $self->getCommentById($ID, $COMNUM);
		unless(defined($Comment)) {
			return $self->DisplayError("No comment found.");
		}
		my $escapedComment = $Comment->Text();
		$COMMENT = uri_unescape($escapedComment);
	}
	my $genericDivID = $self->id.'_'.$COMNUM;
	my $CommentID = 'c_'.$genericDivID;
	my $BlockTextareaID = 'cb_ta_'.$genericDivID;
	my $BlockSubmitID = 'cb_act_'.$genericDivID;
	my $CommentFormID = 'c_f_'.$genericDivID;
	my $TempOutputID = 'c_tmp_'.$genericDivID;
	my $buttons;
	if($COMNUM ne '-2') {
		$buttons = '<a href="javascript:execute_ajax('."'cancel', '$CommentID', ".
			 "'$CommentFormID', 'Loading...', '0', postedit,".
			" 'Comment|$componentID');".'">Cancel</a>'.
			' <a href="javascript:execute_ajax('."'add',".
			" '$CommentID', '$CommentFormID', 'Loading...', '0',".
			" postedit, 'Comment|$componentID');".
			'"/>Save</a>';
	} else {
		$buttons = ' <a href="javascript:prehook('."'$CommentID', 'add',".
			" 'TmpComment', '$CommentFormID', 'Loading...', '0',".
			" postadd, 'Comment|$componentID');".
			'"/>Save</a>';
	}
	$outstr .=  "<div class='CommentBlock'>
				<form id='$CommentFormID'>". 
				"<input type='hidden' name='id' value='$ID' />".
				"<input type='hidden' name='comnum' value='$COMNUM' />".
				"<div class='CommentBlock_Textarea' id='$BlockTextareaID'>".
				"<TEXTAREA name='comment' wrap='soft' rows='15' cols='40'>$COMMENT".
				"</TEXTAREA></div><div class='CommentBlock_EditSubmit' id='$BlockSubmitID'>".
				"</form>".$buttons.'</div></div>';
	return $outstr;
}
=item * B<DisplayLinkBadage> ()
Takes: $self, $ID, [$link]
	where $link = page to goto when clicked
=cut
sub DisplayLinkBadge {
	my ($self, $ID, $link) = @_;
	my $Comments = $self->getCommentsByReferenceObject($ID);
	my $CommentCount = 0;
	if(defined($Comments) && @{$Comments}) {
		$CommentCount = @{$Comments};
	}
	my $outstr = "<a href='$link' class='ConversationBadge'>".
		"<div class='CommentCount'>$CommentCount</div><div>comments</div></a>";
	return $outstr;
}
sub DisplayLinkInlineBadge {
	my ($self, $ID, $link) = @_;
	my $NumberOfComments = $self->getNumberOfComments($ID);
	my $outstr = "<a href='$link' class='ConversationInlineBadge'>".
		"<div class='CommentCount'>$NumberOfComments</div><div>comments</div></a>";
	return $outstr;
}
=item * B<DisplayConversation> ()
Takes: $ID
=cut
sub DisplayConversation {
	my ($self, $ReferenceObj) = @_;
	my $cvDiv = 'cv_'.$ReferenceObj;
	my $title = $self->title();
	my $ID = $self->id;
	my $outstr = "<div class='Conversation' id='$ID'>";
	$outstr .= "<div class='ConversationHeader' onClick='CommentsToggle();'>".
				"$title</div>";
	
	my $Comments = $self->getCommentsByReferenceObject($ReferenceObj);
	
	foreach my $Comment (@{$Comments}) {
		$outstr .= $self->DisplayComment($Comment);	
	}
	my $USEROBJ = $self->application()->session()->user();
	if(defined($USEROBJ)) {
		my $USER = $USEROBJ->login();
		if( $self->canEdit() ) {
			$outstr .= "<div class='Comment' id='c_$ID"."_-2'>";
			$outstr .= $self->DisplayEdit($ReferenceObj, '-2');
			$outstr .= "</div>";
		}
	} else { 
		$outstr .= "<div class='Comment' id='none'><div class=CommentBlock>
					You must login to comment.</div></div>";
	}
	$outstr .= "</div>";
	return $outstr;
}
	
=item * B<DisplayComment> ()
Takes: $ID, $USER, $COMNUM, $COMMENT
Displays the Comment Item div
=cut
sub DisplayComment {
	my ($self, $CommentObj) = @_;
	my $ID = $self->id;
	my $genericDivID = $ID.'_'.$CommentObj->_id();
	my $CommentID = 'c_'.$genericDivID;
	my $outstr = "<div class='Comment' id='$CommentID'>";
	$outstr .= $self->DisplayCommentContents($CommentObj);
	$outstr .= "</div>";
	return $outstr;
}

=item * B<DisplayCommentContents> ()
Takes: $ID, $USER, $COMNUM, $COMMENT
Displays the contents of the Comment Item div
=cut
sub DisplayCommentContents {
	my ($self, $CommentObj) = @_;
	my $ID = $self->id;
	my $genericDivID = $ID.'_'.$CommentObj->_id();
	my $CommentID = 'c_'.$genericDivID;
	my $CommentEditID = 'c_es_'.$genericDivID;
	my $outstr = $self->DisplayCommentBlock($CommentObj);
	my $Username = $CommentObj->User()->login();
	$outstr .= "<div class='CommentInfo'>
				<span class='CommentName'>Posted by $Username</span>";
	$outstr .= $self->DisplayTime($CommentObj->Date());
	if($self->canEdit($CommentObj)) {
		$outstr .= "<span class='CommentEdit' id='".$CommentEditID.
				"'> | <a href='".'javascript:execute_ajax("edit", "'.
				$CommentID.'", "conv='.$CommentObj->ReferenceObject().'&comnum='.
				$CommentObj->_id().'", "Loading...", 0, postedit, "Comments|'.
				$self->{_id}.'");'."'>Edit</a></span>";
	}
	$outstr .= "</div>";
	return $outstr;	
}

=item * B<DisplayCommentBlock> ()
Takes: $ID, $USER, $COMNUM, $COMMENT
=cut
sub DisplayCommentBlock {
	my ($self, $CommentObj) = @_;
	my $ID = $self->id;
	my $CommentText = uri_unescape($CommentObj->Text());
	my $genericDivID = $ID.'_'.$CommentObj->_id();
	my $CommentBlockID = 'c_cb_'.$genericDivID;
	my $outstr = "<div class='CommentBlock' id='".$CommentBlockID."'>$CommentText</div>";
	return $outstr;
}

# year-month-day hour:minute:second
sub DisplayTime {
	my ($self, $timestamp) = @_;
	$timestamp =~ /^(\d+)-(\d+)-(\d+) (\d+)\:(\d+)\:(\d+)$/;
	my $month_name = (January, February, March, April, May, June, July, August, 
				September, October, November, December)[$2-1];
	my $ISO8601_str = "$1-$2-$3"."T".$4.":".$5.":".$6."Z";
	my $date_str = "$month_name $3, $1";
	return " <span class='CommentTime' title='$ISO8601_str'>$date_str</span>";
}

sub DisplayError {
	my ($self, $errorStr) = @_;
	if($DEBUG) { die $errorStr; }
	else { return "<div class='CommentError'>Error: " . $errorStr . "</div>"; }
}
		
### Database METHODS ###
# Returns the comment type of the ID where
# CommentNumber for all rows of Single-Comment IDs is -1
# Returns either: SINGLE COMMENT or MULTI COMMENT
sub getConversationDB {
	my ($self) = @_;
	return $self->{'db'};
}

sub setComment {
	my ($self, $cHash) = @_;
	unless(defined($cHash)) { $self->DisplayError("failed to process comment"); }
	my $db = $self->getConversationDB();	
	unless($cHash->{'_id'} == -2) {
		my $OldComment = $db->Comment->get_objects( { ReferenceObject => 
				$cHash->{'ReferenceObject'}, _id => $cHash->{'_id'} } );
		unless(defined($OldComment)) { return undef; }
		$OldComment = $OldComment->[0];
		$OldComment->Date( _timestamp() );
		$OldComment->Text( $cHash->{'Text'} );
		$OldComment->Page( $self->application->cgi->param('page') );
		$OldComment->Cgi( '' );
		return $OldComment;
	}
	my $user = $self->application->session->user();
	my $NewComment = $db->Comment->create( { ReferenceObject => $cHash->{'ReferenceObject'},
		User => $user, Date => _timestamp(), Text => $cHash->{'Text'}, Page => $Page, Cgi => $Cgi });
	return $NewComment;
}

# Returns a DBTable row (hash of lists) on input items
# or returns undef if it couldn't find or found more than one.
sub getCommentById {
	my ($self, $ReferenceObject, $id) = @_;
	unless(defined($id)) { return undef; }
	unless(defined($ReferenceObject)) { return undef; } 	
	my $db = $self->getConversationDB();
	my $comment = $db->Comment->get_objects( { ReferenceObject => $ReferenceObject, _id => $id } );
	unless(defined($comment)) { return undef; }
	return $comment->[0];	
}

sub getCommentsByURL {
	my ($self, $Page, $Cgi) = @_;
	my $db = $self->getConversationDB();
	my $Comments = $db->Comment->get_objects({ Page => $Page, Cgi => $Cgi});
	unless(defined($Comments)) { return undef}
	return $self->myComments($Comments);
}

sub getCommentsByReferenceObject {
	my ($self, $ReferenceObject) = @_;
	my $db = $self->getConversationDB();
	my $Comments = $db->Comment->get_objects({ ReferenceObject => $ReferenceObject });
	unless(defined($Comments)) { return []; }
	return $self->myComments($Comments);
}

sub myComments {
	my ($self, $Comments) = @_;
	my $db = $self->getConversationDB();
	my $User = $self->application()->session()->user();
	my $viewable;
	for(my $i=0; $i < @{$Comments}; $i++) {
		unless(defined($Comments->[$i])) { next; }
		if($Comments->[$i]->Private()) {
			if(defined($db->CommentDirectedAt->get_objects( 
				{ Comment => $Comments->[$i], User => $User }))) {
				push(@{$viewable}, $Comments->[$i]);
			}
		} else { push(@{$viewable}, $Comments->[$i]); }
	}
	return $viewable;
}
		

sub _timestamp {
	my $self = shift;
	my ($sec,$min,$hour,$day,$month,$year) = gmtime(time());
	$year += 1900;
	$month += 1;
	return $year."-".$month."-".$day.' '.$hour.':'.$min.':'.$sec;
}

sub require_javascript {
	return ['./Html/Comments.js', './Html/jquery.timeago.js', './Html/jquery-1.3.2.min.js'];
}

sub require_css {
	return './Html/Comments.css';
}

