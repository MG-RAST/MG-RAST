package AnnotationClearingHouse::WebPage::comments;

use strict;
use warnings;

use FIG;
use AnnoClearinghouse;
use base qw( WebPage );

1;

sub init{
    my ($self) = @_;

    my $fig = new FIG;
    $self->data('fig' , $fig);
    my $anno = new AnnoClearinghouse($Config::clearinghouse_data,
				     $Config::clearinghouse_contrib,
				     0,
				     my $dbf = $fig->db_handle);

    $self->data('ach' , $anno);
    # register components
    $self->application->register_component('Table','Comment' ); 


    # register actions (if cgi->param('action) = value)
    $self->application->register_action( $self, 'add_comment' , 'Submit Comment' );
}


sub output {
    my ($self) = @_;

    # my $fig = $self->application->data_handle('FIG');
    
    my $cgi = $self->application->cgi();
    my $html = [];
    my $fig = $self->data('fig');

    # User name and login from the WebApplication
    my $user   = $self->application->session->user;
    my $uname  = $user->firstname." ".$user->lastname if ($user and ref $user); 
    my $login  = $user->login                         if ($user and ref $user); 
   
    my $expert = $cgi->param('expert') || $uname;
    my $id     = $cgi->param('id');
    my $funcA  = $cgi->param('funcA'); 
    my $funcB  = $cgi->param('funcB');
    my $md5    = $fig->md5_of_peg($id);

    my $dbf = $fig->db_handle;

    push(@$html,$cgi->h1("ACH Resolution - Possible Conflicts")); 
    push(@$html,"<p>You are coming from <b>$id</b> and adding comments for <b>$funcA</b>  versus  <b>$funcB</b> </p>");


    my $input_comment = [];
    push @$input_comment , "<h3>$expert, please enter your comment here:</h3>";
    push @$input_comment , "<textarea cols='100' rows=15 name='new_comment' wrap='hard'></textarea><br>";
    push @$input_comment , "<input type=submit name='action' value='Submit Comment'>";

    my @hidden;
    push @hidden , "<input type=hidden name='id'     value='$id'>";
    push @hidden , "<input type=hidden name='expert' value='$expert'>";
    push @hidden , "<input type=hidden name='funcA' value='$funcA'>";
    push @hidden , "<input type=hidden name='funcB' value='$funcB'>";

    my $data = &get_comments($fig,$id);


    my $table = $self->application->component('Comment');
    $table->data($data);
    $table->columns( [ { 'name' => 'Commentator',filter => 1, sortable => 1 },
		       { 'name' => 'Date', 'filter' => 1 },
		       { 'name' => 'Comment' }
		     ]
                   );
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(20);
    $table->show_select_items_per_page(1);
    
    push @$html , $self->start_form();
    push @$html , $table->output();
    push @$html , "<br>",@$input_comment;
    push @$html , @hidden;
    push @$html , $self->end_form();


    return join("",@$html);
}



sub add_comment{
  my ($self) = @_;
  
  # init 
  my $success = 0;
  
  my $app = $self->application;
  my $cgi = $self->application->cgi;
  my $ach = $self->data('ach');
  my $fig = $self->data('fig');
  my $dbf = $fig->db_handle;

  # get data
  my $comment = $cgi->param('new_comment');
  my $id      = $cgi->param('id');
  my $expert  = $cgi->param('expert');
  my $md5     = $ach->md5_of_peg($id);
  my $date    = time;

  # check data
  
  $app->add_message('warning' , "There is no comment.") unless ($comment);

  # quote comment
  #$comment =~s/\n/\n<br>/g;
  my $commentQ = quotemeta $comment;

  # insert comment into DB
  if ($expert and $id and $comment and $md5 and $date){

  $dbf->SQL("INSERT INTO ACH_Comment_on_sequence_function (id ,who , ts , md5 ,comment) VALUES ('$id' ,'$expert' , '$date' , '$md5' , '$commentQ')");
  #$app->add_message('info' , length ($comment) );
  
  }
  else{
      $app->add_message('warning' , "Something wrong. No comment inserted! <br> ID : $id <br> You: $expert <br>Date: $date <br>MD5: $md5 <br>Comment: $comment ")
  }

  return $success;
}

sub get_comments {
    my($fig,$id) = @_;

    my $dbf = $fig->db_handle;
    my $md5 = $fig->md5_of_peg($id);
    if ($md5)
    {
	my $comments = $dbf->SQL("SELECT who,ts,comment FROM ACH_Comment_on_sequence_function WHERE
                                  md5 = '$md5'");
	
	my $reformatted = [map { [$_->[0],&FIG::epoch_to_readable($_->[1]),"<pre>".$_->[2]."</pre>"] } @$comments];	
	#my $reformatted = [map { [$_->[0],&FIG::epoch_to_readable($_->[1]),$_->[2]] } @$comments];
	return $reformatted;
    }
    return [];
}

