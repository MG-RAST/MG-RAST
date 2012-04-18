package WebComponent::FormWizard::OOD_Sequencer;

use strict;
use warnings;
use Data::Dumper;
use CGI;

sub new{
    my ($class , $wizard , $question , $value) = @_;
    my $self = { question => $question ,
		 value    => $value || '' ,
		 wizard   => $wizard,
		 page     => $wizard->page,
	     };

    bless $self;
    return $self;
}

sub question{
    my ($self,$question) = @_;

    if ($question and ref $question){
	$self->{question} = $question
    }

    return $self->{question};
}

sub page{
  my ($self) = @_;
  return $self->{page};
}

sub wizard{
    my ($self,$wizard) = @_;

    if ($wizard and ref $wizard){
        $self->{wizard} = $wizard
	}

    return $self->{wizard};
}

sub value{
    my ($self,$value) = @_;

    if ($value){
        $self->{value} = $value
	}

    return $self->{value};
}



sub output {
  my ($self) = @_;

  my $page = $self->wizard->page;

  my $ood  = $page->app->data_handle('OOD');
  $page->app->add_message('warnings', "Ontology databases ".$ood->module_name) unless ($ood and ref $ood);

  my $content = '';

  if ($ood){
    
    # change it back to name  => $self->question->{type} 
    my $cats     =  $ood->Category->get_objects( { name => 'Sequencer' } );
    my $category =  $cats->[0] ;
  
   
    
    my $list = {} ;
    my @labels ; 
    my @values;
    $self->get_list($ood , $category, '' , '' , $list  );

    push @labels , "Please select";
    foreach my $label (sort (keys %$list) ){
      push @labels , $label ;
      push @values , $list->{ $label };
    }
    
    $content .=  $page->application->cgi->popup_menu(-name=>$self->question->{ name },
						     -values=> \@labels ,
						     #-labels=> $list,
						     -default=>  $self->question->{default},
						    );
    

    $page->application->register_component('FilterSelect', 'FilterSelect'. $self->question->{ name } );

    my $filter_select_component = $page->application->component('FilterSelect' .  $self->question->{ name });
    $filter_select_component->labels( \@labels );
    $filter_select_component->values( \@values );
    $filter_select_component->size(8);
    $filter_select_component->width(200);
    $filter_select_component->name( $self->question->{ name });
   

    #$content .= "<input type='hidden' name='".$self->question->{name}."' value='".$self->question->{default}."' id='".$self->question->{name}."'>"; 
    my $table = "<table><tr><td>";
    $table .= "</td><td>" .$filter_select_component->output;
    $table .= "</td><td><a href=\"?page=ManageOOD&category=".$category->ID."&task=edit\">add term</a>";
    $table .= "</td></tr></table>\n";
    # $content .= $table;
  }
  
  return $content;
}


sub get_list{
  my ($self, $ood  , $cat  , $entry , $name , $list ) = @_;
  

  $self->wizard->page->app->add_message('warning', "No Ontology databases") unless ($ood);

  # get object for Category 
  unless(ref $cat){
    my $vars = $ood->Category->get_objects( { ID => $cat } );
    unless(ref $vars and scalar @$vars > 0){
       $self->wizard->page->app->add_message('warning', "No category $cat to fill list");
    }
    $cat = $vars->[0];
  }
 


  if (ref $entry) {
    my $children = $ood->Entry->get_objects( { parent => $entry } );

    
    if($name){
      $name = $name."::".$entry->name;
    }
    else{
      $name = $entry->name;
    }

    if (scalar @$children){

      foreach my $child (@$children){
	$self->get_list( $ood  , $cat , $child , $name , $list);
      }
    }
    else{
      $list->{$name} = $entry->_id;
    }
  }
  elsif ($cat) {
    my $children = $ood->Entry->get_objects( { parent => undef ,
					       category => $cat} );  
    
    foreach my $child (@$children){ 
      $self->get_list( $ood, $cat, $child , $name , $list  );
    }

  }
 
}







sub set_scripts{
  my ($self , $target , $id) = @_;
  my $content ='<script>';
  
  #  var message = \"Active node is \" + value;
  #  alert(message);
  #  document.getElementById(\"filter_select_textbox_".$id."\").value = value;


  $content .= "function set_$target (value){
  document.getElementById(\"".$target."\").value = value;
  document.getElementById(\"".$target."_$id\").firstChild.nodeValue = value;
  }\n";
  $content .= "</script>";
  return $content;
}

sub set_button_field_for_tree{
  my ($name , $value) = @_;
  my $button =" <a onclick=\"set_$name('$value');\"> $value </a>";
  
  return $button;
}




1;
