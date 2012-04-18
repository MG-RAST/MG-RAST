package AnnotationClearingHouse::WebPage::myAssertions;

use strict;
use warnings;

use FIG;

use base qw( WebPage );

1;

sub init{
    my ($self) = @_;

    $self->application->register_component('Table','Assertions' );
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
    my $diffs = $dbf->SQL("SELECT id, function, url expert  FROM 
                       ACH_Assertion WHERE expert = '$expert' and not function='' order by id");
    $self->app->add_message('info' , "Assertions " . scalar @$diffs );
    my $tab = &make_table($diffs,$expert,$cgi,$fig);
    my $table = $self->application->component('Assertions');
    $table->data($tab);
    $table->columns( [ { 'name' => 'ID' , filter => 1 , sortable => 1},
		       { 'name' => 'Functon', filter => 1, operator => 'combobox' , sortable => 1 },
		       { 'name' => 'URL', 'filter' => 1 },
		     ]
                   );
    $table->show_top_browse(1);
    $table->show_bottom_browse(1);
    $table->items_per_page(500);
    $table->show_select_items_per_page(1);

    push(@$html,$cgi->h1("ACH Resolution - My Assertions")); 
    push(@$html,"<p>Dear $uname, you have submitted following IDs with assertions:</p>");

    push @$html , $table->output();

    return join("",@$html);
}

sub make_table {
    my($diffs,$expert,$cgi,$fig) = @_;
    
   
    return [map 
	    { 
		my($id1,$func1,$url) = @$_;
		my $idL1 = &prot_link($cgi,$expert,$id1);
		
		if ($idL1){
		    [$idL1,$func1,$url] 
		    }
	    } @$diffs ];
}

use HTML;

sub prot_link {
    my($cgi,$expert,$prot) = @_;

    if ($prot =~ /^fig\|/)
    {
	if (my $ann = &annotator($expert))
	{
	    return "<a href='http://anno-3.nmpdr.org/anno/FIG/seedviewer.cgi?page=Annotation&feature=$prot&user=$ann'>$prot</a>";
	}
	else
	{
	    return "<a href='http://www.nmpdr.org//FIG/seedviewer.cgi?feature=$prot&page=Annotation'>$prot</a>";
	}
    }
    return &HTML::set_prot_links($cgi,$prot);
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


