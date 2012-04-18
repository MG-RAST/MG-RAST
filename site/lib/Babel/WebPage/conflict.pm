package AnnotationClearingHouse::WebPage::conflict;

use strict;
use warnings;

use FIG;

use base qw( WebPage );

1;

sub init{
    my ($self) = @_;

    $self->application->register_component('Table','Conflicts' );
}


sub output {
    my ($self) = @_;

#    my $fig = $self->application->data_handle('FIG');
    my $fig = new FIG;
    my $cgi = $self->application->cgi();
    my $html = [];

    # User name and login from the WebApplication
    my $user   = $self->application->session->user;
    my $uname  = $user->firstname." ".$user->lastname if ($user and ref $user); 
    my $login  = $user->login                         if ($user and ref $user);  
    
    my $expert = $cgi->param('expert') || $login;
    my $dbf = $fig->db_handle;

    # get data
    my $diffs = $dbf->SQL("SELECT t1.id,t1.function,t1.expert,t2.id,t2.function,t2.expert , count(t1.function)FROM 
                       ACH_Assertion as t1, ACH_Assertion as t2, ACH_Correspondence WHERE
                       ACH_Correspondence.status = 'd' AND 
                       t1.function = ACH_Correspondence.function1 AND 
                       t2.function = ACH_Correspondence.function2 AND
                       (t1.md5 = t2.md5) AND
                       ((t1.expert = '$expert') OR (t2.expert = '$expert'))
                       group by t1.function , t2.function
                     ");
    $self->app->add_message('info' , "There are " . scalar @$diffs . " function pairs marked as different.");
    my $tab = $self->make_table($diffs,$cgi,$fig);
    my $table = $self->application->component('Conflicts');
    $table->data($tab);
    $table->columns( [ { 'name' => 'Example ID1' },
		       { 'name' => 'Function1',filter => 1, sortable => 1 },
		       { 'name' => 'Expert1', 'filter' => 1 },
		       { 'name' => 'Example ID2' },
		       { 'name' => 'Function2',filter => 1, sortable => 1 },
		       { 'name' => 'Expert2', 'filter' => 1, sortable => 1 },
		       { 'name' => 'Number of ID pairs with this functions', 'filter' => 1, sortable => 1 },
		       { 'name' => 'Comments' },
		       { 'name' => 'Add Comment' }
		     ]
                   );
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(500);
    $table->show_select_items_per_page(1);

    push(@$html,$cgi->h2("ACH Resolution - Different functions")); 
    push(@$html,"<p>Dear $expert, this is a list of function pairs marked as different. Those functions are paired because they share the same underlaying sequence. Please check and comment on the following conflicts:</p>");

    push @$html , $table->output();

    return join("",@$html);
}

sub make_table {
    my($self,$diffs,$cgi,$fig) = @_;
    
    my $user   = $self->application->session->user;
    my $expert = $cgi->param('expert');
    
    return [map { 
	          my($id1,$func1,$exp1,$id2,$func2,$exp2,$count) = @$_;
		  if (&outdated($fig,$id1,$func1) || &outdated($fig,$id2,$func2))
		  {
		      ()
		  }
		  else
		  {
		      my $show = &show_comments_url($fig,$cgi,$id1,$func1, $func2,$expert);
		      my $add  = &add_comment_url($cgi,$id1,$func1, $func2, $expert);
		      my $idL1 = &prot_link($cgi,$user,$id1);
		      my $idL2 = &prot_link($cgi,$user,$id2);
		      $count   = &count_link($cgi , $count ,$exp1, $exp2 , $func1, $func2);
		      if ($exp1 eq $expert) {
			[$idL1,$func1,$exp1,$idL2,$func2,$exp2,$count,$show,$add] }
		      else{
			$show = &show_comments_url($fig,$cgi,$id2,$func2, $func1,$expert);
			$add  = &add_comment_url($cgi,$id2,$func2, $func1,$expert);
			[$idL2,$func2,$exp2,$idL1,$func1,$exp1,$count,$show,$add]
		      }
		  }
		 } @$diffs ];
}

sub outdated {
    my($fig,$id,$func) = @_;

    if ($id =~ /^fig\|/)
    {
	my $func2 = $fig->function_of($id);
	# return $func ne $func2;
    }
    return 0;
}

use HTML;

sub prot_link {
    my($cgi,$user,$prot) = @_;

    if ($prot =~ /^fig\|/)
    {
	if ( ref $user and $user->has_scope("Annotators") )
	{
	    my $ann = $user->login;
	    return "<a href='http://anno-3.nmpdr.org/anno/FIG/seedviewer.cgi?page=Annotation&feature=$prot&user=$ann'>$prot</a>";
	}
	else
	{
	    return "<a href='http://www.nmpdr.org//FIG/seedviewer.cgi?feature=$prot&page=Annotation'>$prot</a>";
	}
    }
    return &HTML::set_prot_links($cgi,$prot);
}

sub count_link{
  my ($cgi, $count , $exp1, $exp2 , $func1, $func2) = @_;

  return "<a href='?page=conflict_single&exp1=$exp1&&exp2=$exp2&funcA=$func1&funcB=$func2'>".$count."</a>";
}

sub show_comments_url {
    my($fig,$cgi,$id,$funcA,$funcB,$expert) = @_;

    my $md5 = $fig->md5_of_peg($id);
    if ($md5)
    {
	my $dbf = $fig->db_handle;
	my $comments = $dbf->SQL("SELECT id FROM ACH_Comment_on_sequence_function WHERE md5 = '$md5'");
	if (@$comments > 0)
	{
	    return "<a href='?page=comments&id=$id&funcA=$funcA&funcB=$funcB&expert=$expert'>".scalar @$comments."</a>";
	}
    }
    return "0";
}

sub add_comment_url {
    my($cgi,$id,$funcA,$funcB,$expert) = @_;

    return "<a href='?page=comments&id=$id&funcA=$funcA&funcB=$funcB&expert=$expert'>*</a>";
}

sub annotator {
    my($who) = @_;

    if     ($who eq "Andrei Osterman")         { return "AndreO" }
    elsif  ($who eq "Carol Bonner")            { return "cbonner" }
    elsif  ($who eq "Dimitry Rodionov")        { return "rodionov" }
    elsif  ($who eq "Gary Olsen")              { return "gjo" }
    elsif  ($who eq "Olga Vasieva")            { return "OlgaV" }
    elsif  ($who eq "Olga Zanitko")            { return "OlgaZ" }
    elsif  ($who eq "Ross Overbeek")           { return "RossO" }
    elsif  ($who eq "Svetlana Gerdes")         { return "SvetaG" }
    elsif  ($who eq "Valerie de Crecy-Lagard") { return "vcrecy" }
    elsif  ($who eq "Veronika Vonstein")       { return "VeronikaV" }
    elsif  ($who eq "Daniela Bartels")         { return "DanielaB" }
    
    return undef;
}


