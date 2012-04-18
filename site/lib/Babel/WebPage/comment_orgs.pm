package AnnotationClearingHouse::WebPage::comment_orgs;

use strict;
use warnings;

use FIG;

use base qw( WebPage );

1;

sub init{
    my ($self) = @_;

    my $fig = new FIG;
    $self->data('fig' , $fig);

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
    my $source     = $cgi->param('source');
    my $seed_org  = $cgi->param('seed'); 
    my $external  = $cgi->param('external');

    my $id = "$seed_org"."_$external";

    my $dbf = $fig->db_handle;

    push(@$html,$cgi->h1("Organism Mappinmg - Comment")); 
    push(@$html,"<p>You are adding comments for <b>$seed_org</b>  versus  <b>$external</b> </p>");


    my $input_comment = [];
    push @$input_comment , "<h3>$expert, please enter your comment here:</h3>";
    push @$input_comment , "<textarea cols='100' rows=15 name='new_comment' wrap='hard'></textarea><br>";
    push @$input_comment , "<input type=submit name='action' value='Submit Comment'>";

    my @hidden;
    push @hidden , "<input type=hidden name='id'     value='$id'>";
    push @hidden , "<input type=hidden name='expert' value='$expert'>";
    push @hidden , "<input type=hidden name='source' value='$source'>";
    push @hidden , "<input type=hidden name='seed' value='$seed_org'>";
    push @hidden , "<input type=hidden name='external' value='$external'>";

    my @data = &get_comments($id);


  #   my $table = $self->application->component('Comment');
#     $table->data($data);
#     $table->columns( [ { 'name' => 'Commentator',filter => 1, sortable => 1 },
# 		       { 'name' => 'Date', 'filter' => 1 },
# 		       { 'name' => 'Comment' }
# 		     ]
#                    );
#     $table->show_top_browse(1);
#     $table->show_bottom_browse(1);
#     $table->items_per_page(20);
#     $table->show_select_items_per_page(1);
    
    if (scalar @data){
      push @$html , "<p>";
      push @$html , join "<br>" , @data;
      push @$html , "</p>";
    }

    push @$html , $self->start_form();
    #push @$html , $table->output();
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


  # get data
  my $comment = $cgi->param('new_comment');
  my $id      = $cgi->param('id');
  my $source      = $cgi->param('source');
  my $date    = time;

  # check data
  
  $app->add_message('warning' , "There is no comment.") unless ($comment);

  open(FILE , ">>/vol/clearinghouse/data/comments/$id");
  print FILE "DATE:$date\tSOURCE:$source\n";
  print FILE $comment ."\n";
  close FILE;
}


sub get_comments {
  my($id) = @_;

  my @comment;

  open(FILE , "/vol/clearinghouse/data/comments/$id");
  while( <FILE> ){
    push @comment , $_;
  }

  return @comment;
}

