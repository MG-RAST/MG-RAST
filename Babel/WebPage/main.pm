package AnnotationClearingHouse::WebPage::main;

use strict;
use warnings;

use FIG;

use base qw( WebPage );

1;

sub init {
  my ($self) = @_;

  my $fig = new FIG;
  $self->data('fig' , $fig);
}

sub output {
    my ($self) = @_;

    my $fig = $self->data('fig');
    my $master =  $self->application->dbmaster;
    my $scope_annotators = $master->Scope->get_objects( { name => "Annotators"} )->[0];

    #$self->app->add_message('info' , $scope_annotators->name );

    unless ($fig and ref $fig){
      print STDERR "No data handle FIG";
      exit;
    }

    my $cgi = $self->application->cgi();
    my $html = [];

 

    my $user   = $self->application->session->user;
    my $expert = "";
    $expert = $user->firstname." ".$user->lastname if ($user and ref $user);
    push(@$html,$cgi->h1("ACH Resolution"));

    if ($user and ref $user){
	#push(@$html, "<p>Welcome ".$expert.",<br>you have uploaded functional assignments for some protein sequences. These assignments may not be syntactical or semantical identical to corresponding expert assignments for the same protein ID or sequence. These are potential conflicts of different functional assignments for the same protein sequence. To identify real conflicts we are building a synonym book. For this please categorize the conflicting corresponding assignments into <b>semantical identical</b> or <b>different</b>. Corresponding functionl assignments marked as different are real conflicts. You can review those conflicts and comment them.<br> <br>Please <ol><li><a href='?page=correspondences'>categorize</a> differences in annotations <li> <a href=\"?page=conflict\">comment conflicts</a> </ol> To view your current assertions please <a href='?page=myAssertions'>click here</a><p>");
      push(@$html, "<p>Welcome ".$expert.",<br>You have uploaded functional assignments for some protein sequences that may not be syntactical or semantically identical to corresponding expert assignments for the same protein ID or sequence. The following are potential conflicts of different functional assignments for the same protein sequence. Please categorize the conflicting assignments <b>semantically identical</b> or <b>different</b>. You can  review the conflicting assignments marked as <b>different</b> (not semantically identical) and comment on them. <br> <br>Please <ol><li><a href='?page=correspondences'>categorize</a> differences in annotations <li> <a href=\"?page=conflict\">comment conflicts</a></ol> To view your current assertions please <a href='?page=myAssertions'>click here</a><p>");
      
      my $table = "<table><tr>\n";
      $table .= "<th>Uncategorized correspondences:</th><td>".$self->get_unhandeld_diffs_for_user($user->login) || "0"."</td>";
      $table .= "</tr><tr>\n";
      $table .= "<th>Categorized correspondences:</th><td><a href='?page=correspondences&status=handled'>".$self->get_handeld_diffs_for_user($user->login) || "0"."</a></td>";
      $table .= "</tr><tr>\n";
      $table .= "<th>Conflicts:</th><td>". $self->get_conflicts_for_user($user->login) ."</td>\n";
      $table .= "</tr></table>\n";
      push(@$html, $table);
  
      my $ross_tool = "<p>Goto SEED to <a href='http://anno-3.nmpdr.org/anno/FIG/ex_assertions.cgi'>resubmit expert annotations</a></p>";
      push @$html , $ross_tool if  $user->has_scope("Annotators");
   
   #    if ( $user->is_admin('AnnotationClearingHouse') or $user->has_scope("Annotators") ){

# 	if ( $user->is_admin('AnnotationClearingHouse') ){
# 	  push(@$html, "<h3>Admin view</h3>");

# 	  my @experts = &get_experts($fig);
# 	  my $table = "<table>\n";
# 	  foreach my $expert (@experts){
# 	      print STDERR "Getting overview for $expert\n";
# 	      $table .= "<tr>";
# 	      $table .= "<th>$expert</th><th>Uncategorized correspondences:</th><td>".$self->get_unhandeld_diffs_for_user($expert) || "0"."</td>";
# 	      $table .= "</tr><tr>\n";
# 	      $table .= "<td></td><th>Categorized correspondences:</th><td><a href='?page=correspondences&status=handled&expert=$expert'>".$self->get_handeld_diffs_for_user($expert) || "0"."</a></td>";
# 	      $table .= "</tr><tr>\n";
# 	      $table .= "<td></td><th>Conflicts:</th><td>". $self->get_conflicts_for_user($expert) ."</td>\n";
# 	      $table .= "</tr>";
# 	  }
# 	  $table .= "</table>\n";
# 	  push(@$html, $table);
 
# 	}
# 	elsif  ($user->has_scope("Annotators") ) {
# 	  push(@$html, "<h3>Annotator view</h3>"); 
# 	}
# 	my @experts = &get_experts($fig);
# 	push(@$html,$cgi->h4("Show Conflicts Involving a Specific Expert"),
# 	     $self->start_form('ExpertConflicts',{page => 'conflict'}),
# 	     "You can pick an expert and then get a table of all of the conflicts relating to assertions by that expert.<br><br>",
# 	     $cgi->scrolling_list( -name      => "expert",
# 				   -values    => [@experts],
# 				 ),
# 	     $cgi->submit('Display Conflicts'),
# 	     "<br><br>",&edit_corr($fig,$cgi),"<br>\n",
# 	     $self->end_form
# 	    );
#       }
     }

    return join("",@$html);
}

sub edit_corr {
    my($fig,$cgi) = @_;

    return "<a href='?page=correspondences'>To Edit Correspondence Table</a>";
}

sub get_experts {
    my($fig) = @_;

    my $dbf = $fig->db_handle;
    my $experts = $dbf->SQL("SELECT DISTINCT expert FROM ACH_Assertion");
    return sort map { $_->[0] } @$experts;
}



  sub required_rights {
    return [ [ 'login' , ''],
           ];
  }


sub get_unhandeld_diffs_for_user {
  my ($self , $user) = @_;
  my $fig = $self->data('fig');
  my $dbh = $fig->db_handle;
  return unless ($user);
 
  
  my $diffs;
  
  if ($user){
    
    my $statement = "select count(*) from ACH_Correspondence, ACH_Assertion where ( ACH_Correspondence.function1=ACH_Assertion.function or ACH_Correspondence.function2=ACH_Assertion.function ) and ACH_Assertion.expert='".$user."' and ACH_Correspondence.status='' group by ACH_Correspondence.function1 , ACH_Correspondence.function2";
    
    $diffs = $dbh->SQL($statement); 
  }
  
 
  
  return $diffs->[0]->[0];
}

sub get_handeld_diffs_for_user {
  my ($self , $user) = @_;
  my $fig = $self->data('fig');
  my $dbh = $fig->db_handle;
  return unless ($user);
 
  
  my $diffs;
  
  if ($user){
    
    my $statement = "select ACH_Correspondence.function1, ACH_Correspondence.function2, ACH_Correspondence.status from ACH_Correspondence, ACH_Assertion where ( ACH_Correspondence.function1=ACH_Assertion.function or ACH_Correspondence.function2=ACH_Assertion.function ) and ACH_Assertion.expert='".$user."' and not ACH_Correspondence.status='' group by ACH_Correspondence.function1, ACH_Correspondence.function2, ACH_Correspondence.status";
    
    $diffs = $dbh->SQL($statement); 
  }
  
 
  return scalar @$diffs;
  return $diffs->[0]->[0];
}



sub get_conflicts_for_user {
  my ($self , $user) = @_;
  my $fig = $self->data('fig');
  my $dbh = $fig->db_handle;
  return "HALLO" unless ($user);
 
  
  my $diffs;
  
  if ($user){

    my $statement = "SELECT count(*) FROM 
                       ACH_Assertion as t1, ACH_Assertion as t2, ACH_Correspondence WHERE
                       ACH_Correspondence.status = 'd' AND 
                       t1.function = ACH_Correspondence.function1 AND 
                       t2.function = ACH_Correspondence.function2 AND
                       (t1.md5 = t2.md5) AND
                       ((t1.expert = '$user') OR (t2.expert = '$user'))
                     ";
  # get data
    $diffs = $dbh->SQL($statement);
    # $self->app->add_message('info' , $statement . " :::: " . $diffs->[0]->[0]);
  } 
  else{
    $self->app->add_message('warning' , "No user $user");
  }
  return $diffs->[0]->[0];
}
