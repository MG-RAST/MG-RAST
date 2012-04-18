package AnnotationClearingHouse::WebPage::correspondences;

use strict;
use warnings;

use FIG;

use base qw( WebPage );

1;

sub init{
    my ($self) = @_;

    $self->application->register_component('Table','Correspondences' );
    my $fig = new FIG;
    my $ach = $self->application->data_handle('ACH');
    $self->data('fig',$fig); 
    $self->data('ach',$ach);

    $self->application->register_action($self, 'update_correspondances', 'Submit selection');
}


sub output {
    my ($self) = @_;

    my $fig = $self->data('fig');
    my $cgi = $self->application->cgi();

    my $debug = $cgi->param('debug') || 0 ;
    $self->data('debug' , $debug);

    my $html = [];
    my $handled = $cgi->param('status') || '';

    push(@$html,$cgi->h1("ACH Resolution - Correspondences"));

    push(@$html , "<p>Below is a list of corresponding functional assignments sharing the same protein sequence. Since these functional assignments are not syntactically identical please jugde if they are <b>in conflict</b> to each other or <b>not in conflict</b>.</p>" );
    my $expert = $cgi->param('expert');
    
    my $dbf = $self->data('ach');

    my $diffs = $self->get_ach_diffs();
    #my $tab = $diffs;
    my $tab = &make_table($diffs , $cgi);
    my $table = $self->application->component('Correspondences');
    $table->data($tab);
    $table->columns( [ 
		       { 'name' => 'Function 1',filter => 1, sortable => 1 },
		       { 'name' => 'Function 2',filter => 1, sortable => 1 },
		       { 'name' => 'Status' , filter =>1 , operator => 'combobox' },
	
		     ]
                   );
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(500);
    $table->show_select_items_per_page(1); 
    $table->show_export_button({ strip_html => 1 });
    if (ref $tab and scalar @$tab){
      push @$html , $self->start_form('Cat');
      push @$html , $table->output(); 
      push @$html , "<p><input type='submit' name='action' value='Submit selection'></p>";
      push @$html , $self->end_form();
    }
    else{
      push @$html , "<p>Sorry, there are no further correspondences to categorize for you.($handled)</p>"; 
    }
    return join("",@$html);
}



sub get_ach_diffs {
  my ($self) = @_;

  # my $dbh  = $self->data('ach');
  my $dbh  = $self->data('fig')->db_handle;
  my $cgi  = $self->app->cgi;
  my $user = $self->application->session->user;
  my $uname  = '';
  $uname     = $user->firstname." ".$user->lastname if ($user and ref $user);

  my $handled = $cgi->param('status')|| '';
  my $expert  = $cgi->param('expert') || $uname;

  print STDERR "Status = $handled\n";
  
  my $diffs; 
  
  if ($user and ref $user){

      my $current_user = $user->login;
      $current_user = $cgi->param('expert') if $cgi->param('expert');
 
      print STDERR "HIER 1\n";
      
      my $statement = "select ACH_Correspondence.function1, ACH_Correspondence.function2, ACH_Correspondence.status from ACH_Correspondence, ACH_Assertion where ( ACH_Correspondence.function1=ACH_Assertion.function or ACH_Correspondence.function2=ACH_Assertion.function ) and  ( ACH_Correspondence.function1!=''and ACH_Correspondence.function2!='' ) and ACH_Assertion.expert='".$current_user."' and ACH_Correspondence.status='' group by ACH_Correspondence.function1, ACH_Correspondence.function2, ACH_Correspondence.status order by ACH_Correspondence.function1, ACH_Correspondence.function2";
      
      if ($handled){
	  $statement = "select ACH_Correspondence.function1, ACH_Correspondence.function2, ACH_Correspondence.status from ACH_Correspondence, ACH_Assertion where ( ACH_Correspondence.function1=ACH_Assertion.function or ACH_Correspondence.function2=ACH_Assertion.function ) and ACH_Assertion.expert='".$current_user."' and not ACH_Correspondence.status='' group by ACH_Correspondence.function1, ACH_Correspondence.function2, ACH_Correspondence.status order by ACH_Correspondence.function1, ACH_Correspondence.function2";     
     
	  print STDERR "HIER 2\n";
      }
    $self->app->add_message('info' , $statement) if ($self->data('debug') );

    $diffs = $dbh->SQL($statement);
    print STDERR "DIFFS: $diffs " . scalar @$diffs ."\n"; 
    
  }
  elsif ($expert){
    print STDERR "MSG: Simple query";
    $diffs = $dbh->SQL("SELECT function1,function2, status FROM ACH_Correspondence");
  }
  else{
      $diffs = $dbh->SQL("SELECT function1,function2, status FROM ACH_Correspondence where status='s'");
  }
  
  
  
  foreach my $tuple (@$diffs) {
      if ($tuple->[2] eq "s") {  $tuple->[2] = "same" }
      elsif ($tuple->[2] eq "d") { $tuple->[2] = "different" }
      elsif ($tuple->[2] eq "i") { $tuple->[2] = "ignore" } 
      elsif ($tuple->[2] eq "") { $tuple->[2] = "unhandled" } 
  }
  
  return $diffs;
}

sub make_table{
    my ($diffs , $cgi) = @_;
    
    foreach my $line (@$diffs){
	my $name="correspondence.".$line->[0]."\t".$line->[1];
	my $checked={ same    => '' ,
		      ignore  => '' ,
		      diffent => '' ,
		      s       => '',
		      d       => '',
		      i       => '',
		  };
	$checked->{ $line->[2] } = "checked" if ($line->[2]);

	my $buttons = "<table><tr><td><input type='radio' name='$name' value='s' ".($checked->{same} || '' )."></td><td>not&nbsp;in&nbsp;conflict</td></tr>
<tr><td><input type='radio' name='$name' value='d' ".($checked->{different} || '')."></td><td>conflict</td></tr>
<tr><td><input type='radio' name='$name' value='i' ".($checked->{ignore} || '')."></td><td>ignore</td></tr></table>";

	push @$line , $buttons;
	push @$line ,  $cgi->popup_menu( -name => "color" ,
					 -values => [ 'In conflict' ,
						      'Synonymic annotations',
						      'Synonymic annotations, but differ in the level of detail',
						      'Nonorthologous gene displacement',
						      'Ignore' ] );
    }
    
    return $diffs;
}

sub update_correspondances{
    my ($self , $comment) = @_;
    
    my $cgi = $self->app->cgi;
    #my $dbh  = $self->data('ach');
    my $dbh  = $self->data('fig')->db_handle;
    my $user = $self->application->session->user;
    my @params = $cgi->param();
    
    foreach my $param (@params){
      if ( my ($prefix , $pair) = $param =~ /(correspondence\.)(.+)/ ){

	my $status =  $cgi->param($param);
	my ($func1 , $func2) = split "\t" , $pair;

	$self->app->add_message('info' , "You set $func1   <b>versus</b> $func2 to <b>" . $cgi->param($param) ."</b>" ) if ($self->data('debug') );

	my $corr = $dbh->SQL("SELECT function1,function2, status FROM ACH_Correspondence where function1='$func1' and function2='$func2'");
	
	if (ref $corr and scalar @$corr){
	  $comment = "" unless ($corr->[0]-[2] and $comment);
	  $corr = $dbh->SQL("UPDATE ACH_Correspondence SET status='$status' where function1='$func1' and function2='$func2'");
     

	}
	else{
	  print STDERR "ERROR: No correspondances in table for '$func1' and '$func2'\n";
	}

      }
    }
    
}
