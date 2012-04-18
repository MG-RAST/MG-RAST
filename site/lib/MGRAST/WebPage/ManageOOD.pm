package MGRAST::WebPage::ManageOOD;

use strict;
use warnings;

use POSIX;
use File::Basename;


use WebConfig;
use base qw( WebPage );
1;


=pod

=head1 NAME

MetaData - collects meta information for uploaded genome or metagenome

=head1 DESCRIPTION

Page for collecting meta data for genomes or metagenomes

=head1 METHODS

=over 4

=item * B<init> ()

Called when the web page is instanciated.

=cut

sub init {
  my $self = shift;

  $self->title("Manage (MG) Rast Ontology On Demand");

  my $ood = $self->app->data_handle('OOD');
 
  
  # register action

  $self->application->register_action($self, 'add_category', 'Add category');
  $self->application->register_action($self, 'add_entry', 'add_entry'); 
  $self->application->register_action($self, 'delete_entry', 'delete_entry'); 
  $self->application->register_action($self, 'add_datafield', 'Add data field');
  # register components

  $self->application->register_component('TabView', 'Tabs'); 
  $self->application->register_component('Table' , 'CategoryTable');
  $self->application->register_component('FilterSelect', 'ListCategories');
  $self->application->register_component('FilterSelect', 'SelectCategories');
  $self->application->register_component('Tree', 'OntologyTree');
  $self->application->register_component('Tree', 'OntologyTreeData');
  $self->application->register_component('FilterSelect', 'OntologyList');


  my $ontology = { biome => { 
			     freshwater	 => 'ENVO:00000873',
			     marine      => 'ENVO:00000447',
			     terrestrial => 'ENVO:00000446',
			     soil	 => 'ENVO:00001998',
			     water	 => 'ENVO:00002006',
			     air	 => 'ENVO:00002005',
			     sediment	 => 'ENVO:00002007',
			     sludge	 =>  'ENVO:00002044',
			     'waste water'          => 	'ENVO:00002007',
			     'hot spring'	    =>  'ENVO:00000051',
			     'hydrothermal vent'    =>	'ENVO:00000215',
			     'organism-associated'  =>	'ENVO:00002032',
			     'extreme environment'  =>	'ENVO:00002020',
			     food                   =>	'ENVO:00002002',
			     biofilm                =>	'ENVO:00002034',
			     'microbial mat'        =>	'ENVO:01000008',
			     fossil                 =>	'ENVO:00002164',
			    }
		 };
  $self->data('ontology' , $ontology); 
  $self->data('ood' , $ood); 
 
  # set category

  my $cat = $self->application->cgi->param( 'category' ) || $self->application->cgi->param( 'active_category' ) ||  "none" ;
  $self->data('active_category' , $cat);
  


  # set active entry

  my $node = $self->application->cgi->param( 'active_node' ) || "";

  if (  $self->application->cgi->param( 'node' ) and not
	      $self->application->cgi->param( 'node' ) eq "start typing to narrow selection" ){
      
    $node = $self->application->cgi->param( 'node' ) || 'none' ;
      
    
  }
  $self->data('active_node' , $node);

  if  ( $self->application->cgi->param( 'reset_entry' ) ) {
    $self->data('active_node' , undef ); 
    $self->application->cgi->param( 'active_node' , undef );
  }


  # get objects for current category and node
  my $catList = $ood->Category->get_objects( { ID => $cat } );
  
  my $category = undef ;
  my $anode;
  if ( ref $catList and @$catList == 1 ) {
        
    $category = $catList->[0];
    
    if ( $node and !(ref $node) ){
      my ($name) = $node =~/([^\:]+)$/;
      my $vars = $ood->Entry->get_objects( { name     => $node,
					     category => $category, } );
      if (ref $vars and scalar @$vars == 1){
	$anode = $vars->[0];
	$self->data('node_object' , $anode ); 
      }
      else{
	$self->app->add_message('warning', "No or multiple nodes for " . $cat ." and " . $node );
	$self->data('node_object' , undef ); 
      }
    }
    $self->data('category_object' , $category ); 
   
  }
  else{
    $self->app->add_message('warning', "No or multiple categories for " . $cat );
    $self->data('category_object' , undef ); 
    $self->data('node_object' , undef ); 
  }
  


  # remember last task, stay there unless new task is given
  unless ( $self->application->cgi->param('task') ){
    $self->application->cgi->param('task', $self->application->cgi->param('active_task') );
  }
  
  $self->data('task' , $self->application->cgi->param('task') );
  if  ($self->application->cgi->param('task') and  $self->application->cgi->param('task') eq "add_entry"){
    $self->application->cgi->param('task' , "edit");
  }
 #  $self->app->add_message('info', "Current category " . $cat );
#   $self->app->add_message('info',  "Current entry " . $node ); 
#   $self->app->add_message('info',  "Current task " . $self->application->cgi->param('task') || "none");
#   $self->app->add_message('info',  "Current sub task " . $self->data('task') );
  
}


=item * B<output> ()

Returns the html output of the page.

=cut

sub output {
  my ($self) = @_;
  
 
  
  # get data affected by register actions
  # fill list with current categories
  
  my $cgi  = $self->application->cgi;
  my $ood        =  $self->data('ood'); 
  my $categories = $ood->Category->get_objects();

  my $user     = $self->application->session->user;

  my $clist = $self->application->component('ListCategories');
  my @labels;
  my @IDs;

  foreach my $cat (@$categories){
    push @labels , $cat->ID."|".$cat->name;
    push @IDs    , $cat->ID;
  }
  
  $clist->labels( \@labels );
  $clist->values( \@IDs );
  $clist->size(8);
  $clist->width(250);
  $clist->name('CurrentCategories');
  
  $self->data('categories' , $categories);
  $self->data('CategoryList' , $clist);


  
  my $tab_view = $self->application->component('Tabs');
  $tab_view->width(800);
  $tab_view->height(180);
  
 
  my $tree = $self->application->component('OntologyTree'); 
  my $treeData = $self->application->component('OntologyTreeData');
  my $content = $self->set_scripts("active_node"); 

  if ($user->is_admin()){
    $self->application->add_message('info' , 'You are admin');
  }
  else{
    # $self->applicaation->add_message('info' , 'You are not an admin');
  }

  $content .= '<h1>View or edit controlled vocabulary</h1>';
  $content .= "<p>Please complete the form below</p>";
  my $log = '';
  
  if ( ref $self->data('categories') and @{  $self->data('categories') } > 0 ){
    $tab_view->add_tab('Edit Category', $self->display_entries) if ($cgi->param('task') eq "edit");
    $tab_view->add_tab('Add Categories', $self->display_edit_category) if ($cgi->param('task') eq "add_category"  and ( $user->is_admin() or $user->login eq "awilke") );
    $tab_view->add_tab('Edit data fields for ' . $self->data('active_node') , $self->display_datafields) if ($cgi->param('task') eq "edit_datafields" and ( $user->is_admin() or $user->login eq "awilke") );
    $tab_view->add_tab('Categories', $self->display_category() ) if ($user->is_admin or $user->login eq "awilke");
    #$tab_view->add_tab('Add Category', $self->display_edit_category) ;
    #$tab_view->add_tab('Add Entries', $self->display_edit_category_entries) ;
    #$tab_view->add_tab('Add Datafields', $self->display_edit_datafields) ;
  }
  else{
    $tab_view->add_tab('Add Categories', $self->display_edit_category);
    $tab_view->add_tab('Categories', $self->display_category() );
  }
  
  $content .= $self->start_form('ManageOOD');
  $content .= "<input type='hidden' name='active_category' value='".$self->data('active_category')."'>";  
  $content .= "<input type='hidden' name='active_node' value='".$self->data('active_node')."' id='active_node'>";  
  $content .= "<input type='hidden' name='active_field' value='".$self->data('active_field')."'>"; 
  $content .= "<input type='hidden' name='active_task' value='".$self->data('task')."'>"; 
  $content .= $tab_view->output;
  $content .= $self->end_form();
  return $content;
}





=item * B<optional_info> ()

Returns the optional info and questions page parts

=cut

sub display_category {
  my ($self) = @_; 
  my $content = "<p>List of OOD categories</p>\n";

  if ( $self->data('active_category') and !($self->data('active_category') eq "none") ) {
    #$content .= "<p>Current category is ".$self->data('active_category').", select new category from list, <a href=\"?page=ManageOOD&task=edit\">edit category</a> or <a onclick=\"submit_form('add_category')\">add new category</a></p>\n";
    $content .= "<p>Current category is ".$self->data('active_category').", select new category from list, ";
    $content.=" <button type=\"submit\" name=\"task\" value=\"edit\" onclick=\"submit\">edit category</button> or ";
    $content .= "<button type=\"submit\" name=\"task\" value=\"add_category\" onclick=\"submit\">add new category</button></p>\n";
  }
  else{
    $content .= "<p>Current category is ".$self->data('active_category').", select new category from list or <a href=\"?page=ManageOOD&task=add_category\">add new category</a></p>\n";
  }
  # get all categories
  my $ood = $self->data('ood');
  my $vars = $ood->Category->get_objects();
 

  if (ref $vars and scalar @$vars > 0){

    my @table_data;
    foreach my $cat (@$vars){
      my $id = "<a href=\"?page=ManageOOD&category=".$cat->ID."\">".$cat->ID."</a>";
      push @table_data , [ $id , $cat->name , $cat->description ];
     
    }


    my $table = $self->application->component('CategoryTable');
    $table->width(800);
    
    if (scalar(@table_data) > 50) {
      $table->show_top_browse(1);
      $table->show_bottom_browse(1);
      $table->items_per_page(50);
      $table->show_select_items_per_page(1); 
    }
  
    $table->columns([ { name => 'ID', sortable => 1, filter => 1 }, 
		      { name => 'Name', sortable => 1 , filter => 1 }, 
		      { name => 'Description' , sortable => 0 },
                    ]);

    $table->data(\@table_data);
    $content .= $table->output();


  }
  else{
 
    $self->app->add_message('warning', "No category in database");
    
  }
  #$content .= $self->data('CategoryList')->output;

  return $content;
}

=pod

=item * B<display_edit_category> ()

Adding a Category to the database

=cut

sub display_edit_category{
  my ($self) = @_;
  
  my $content = $self->start_form('edit_category');
  
 
  my $clist = $self->data("CategoryList");
  #$content .= "<input type='hidden' name='action' value='add_category'>";
  $content .= "<table><tr>\n<td>Existing categories<td>Enter new category<td>Description</tr>\n";
  
  $content .= "<tr><td>" .$clist->output;

 $content .= "<td><input type='text' name='new_category' value=''><td><input type='text' name='new_description' value=''></tr><tr><td><td><td><input type='submit' name='action' value='Add category'>";
  $content .= "</tr></table>\n";

  $content .= $self->end_form();
  
  return $content;
}



sub display_entries{
  my ($self) = @_;
  
  my $tree = $self->application->component('OntologyTree');
  my $olist = $self->application->component("OntologyList");

  my $ood        =  $self->data('ood'); 
 
  my $acat = $self->data('active_category') || "no category";

  if ( $self->data('active_category' ) ) {

    $self->fill_ontology_tree($tree ,  $self->data('active_category' ) , undef , undef , "active_node");

  }

  my $content = "";
  
  if ( $self->data('task') eq "add_entry" ){
    $content .= "<table>\n";
    $content .= "<tr><td>New entry name:<td><input name=\"new_entry\" type='text' size='50'></tr>\n";
    $content .= "<tr><td>Short definition:<td><textarea name=\"entry_definition\" cols=\"50\" rows=\"10\"></textarea></tr>\n";
    $content .= "</table>\n";
    if ($self->data('active_node' ) ){
      $content .= "<button type=\"submit\" name=\"action\" value=\"add_entry\">Add new entry after ".$self->data('active_node' ) ."</button>";
    }
    else{
      $content .= "<button type=\"submit\" name=\"action\" value=\"add_entry\">Add new toplevel entry</button>";
    }
  }
  else{
  
    $content = "<p>Entries for ". $self->data('category_object')->name."($acat)</p>\n";
    $content .= "<table><tr>";
    $content .= "<td>Selected: <div id=\"display_selection\" style=\"font-size:1.0em; background-color:#FFFFCC; padding:10px;border:solid 1px red\">". ($self->data('active_node') || " ") ."</div></td><td>\n";
    $content .=  $tree->output;
    $content .= "</td><td>";
    $content .= "Please select entry from left tree to perform actions.<br>\n";
    $content .= "<ul>";
    if ( $self->data('active_node') ){
      $content .= "<li> <button type=\"submit\" name=\"task\" value=\"add_entry\">Add entry</button> after ". $self->data('active_node');
      $content .= "<li> <button type=\"submit\" name=\"task\" value=\"edit_datafields\">Edit</button> data fields for ". $self->data('active_node')  if ($self->application->session->user->is_admin or $self->application->session->user->login eq "awilke" );
      $content .= "<li><button type=\"submit\" name=\"action\" value=\"delete_entry\">Delete ". $self->data('active_node')."</button>" if $self->data('active_node') ; 
      $content .= "<li><button type=\"submit\" name=\"reset_entry\" value=\"".$self->data('active_node')."\">Reset selection</button>" if $self->data('active_node') ;
    }
    else{
      $content .= "<li><button type=\"submit\" name=\"task\" value=\"add_entry\">Add top level entry</button>";
    }
   
    $content .= "</ul>";
    $content .= "";
    $content .= "</td></tr></table>";
    #"<td><input type='text' name='new_entry' value=''></tr><tr><td><td><td><input type='submit' name='action' value='Add entry'>";
  }
  
   
  return $content;
}



=pod

=item * B<display_edit_category_entries> ()

Adding entries to a category

=cut

sub display_edit_category_entries{
  my ($self) = @_;
  
  my $tree = $self->application->component('OntologyTree');
  my $clist = $self->application->component('SelectCategories');
  my $olist = $self->application->component("OntologyList");

  my $ood        =  $self->data('ood'); 
  my $categories = $ood->Category->get_objects();

  
  my @labels;
  my @IDs;

  foreach my $cat (@$categories){
    print STDERR "here";
    push @labels , $cat->ID."|".$cat->name;
    push @IDs    , $cat->ID;
  }
  
  $clist->labels( \@labels );
  $clist->values( \@IDs ); 
  #$clist->default(   $self->data('active_category' ) );
  $clist->size(8);
  $clist->width(250);
  print STDERR "da";
  $clist->name('SelectCategories');
  print STDERR "du";
  $olist->name('SelectEntry');

  my $acat = $self->data('active_category') || "no category";

  if ( $self->data('active_category' ) and   $self->data('active_category' ) =~ /\w+\|([\w\W]+)/) {
    print STDERR "CATEGORY = $1";
    $self->fill_ontology_tree($tree , $1 , undef , undef , "active_node");
    $self->fill_ontology_list($olist , $1)
  }

  my $content = $self->start_form('edit_entries');
  
 
  $content .= "<input type='hidden' name='active_node' id=\"tree_".$tree->id."\">";
  $content .= "<input type='hidden' name='active_category' value='".$self->data('active_category')."'>";
  $content .= "<table><tr>\n<td>Select category<td>Select node for ".$acat."<td>Add after selected node</tr>\n";
  
  $content .= "<tr><td>" .$clist->output . "<input type='submit' name='category' value='select category'>" ;

 $content .= "<td>". $olist->output . $tree->output."<td><input type='text' name='new_entry' value=''></tr><tr><td><td><td><input type='submit' name='action' value='Add entry'>";
  $content .= "</tr></table>\n";

  $content .= $self->end_form();
  $self->app->add_message('info', "Default: ". $clist->default );

  return $content;
}


sub display_datafields{
  my ($self) = @_;
  
  my $cgi  = $self->application->cgi;
  my $tree = $self->application->component('OntologyTree');

  my $node       = $self->data('active_node');
  my $ood        = $self->data('ood'); 
  my $categories = $ood->Category->get_objects();

  
 

  my $acat = $self->data('active_category') || "no category";

  if ( $self->data('active_category' ) )  {
    
    $self->fill_ontology_tree($tree ,  $self->data('active_category' )  , undef , undef , "active_node" );
    
  }
       
  my $content;
  
 
  $content .= "<table><tr><td>Entries<td>Add data field</tr><tr>";
  
  $content .= "<td>". $tree->output."<td>";
  $content .= "<table>"; 
  $content .= "<tr><td>Name <td><input type='text' name='data_field_name' value=''></tr>\n";
  $content .= "<tr.<td>Type<td> ".$cgi->popup_menu(-name=>"data_field_type",
						   -values=>[ "TEXT",
							      "NUMBER" , 
							      "DATE",
							      "URL",
							      "FILE",
							    ],
						   -default=>"TEXT") . "</tr>" ;
  $content .= "<tr><td>Row<td><input type='text' name='data_field_row' value=''></tr>\n";
  $content .= "<tr><td>Column<td><input type='text' name='data_field_col' value=''></tr>\n";
  $content .= "<tr><td><td><input type='submit' name='action' value='Add data field'></tr>\n";
  $content .= "</table> ";
  $content .= "<td>".$self->get_data_fields_for_entry ;
  $content .= "</tr></table>\n";
  
  
  
  return $content;
}


sub display_edit_datafields{
  my ($self) = @_;
  
  my $cgi  = $self->application->cgi;
  my $tree = $self->application->component('OntologyTreeData');

  my $node       = $self->data('active_node');
  my $ood        = $self->data('ood'); 
  my $categories = $ood->Category->get_objects();

  
 

  my $acat = $self->data('active_category') || "no category";

  if ( $self->data('active_category' ) and   $self->data('active_category' ) =~ /\w+\|([\w\W]+)/) {
 
    $self->fill_ontology_tree($tree , $1 , undef , undef , "active_node_data_field" );
   
  }

  my $content = $self->start_form('edit_entries');

  
  $content .= "<input type='hidden' name='active_node' id=\"tree_".$tree->id."\">";
 
  #$content .= "<input type='hidden' name='active_node' id=\"active_node\">";
  #$content .= "<input type='hidden' name='active_category' value='".$self->data('active_category')."'>";
  $content .= "<table><tr><td>Entries<td>Data fields<td>Add data field</tr><tr>";

 $content .= "<td>". $tree->output."<td>".$self->get_data_fields_for_entry."<td>Name <input type='text' name='data_field_name' value=''><br>Type ".$cgi->popup_menu(-name=>"DataType",
					      -values=>[ "TEXT",
							 "NUMBER" , 
							 "DATE",
							 "URL",
							 "FILE",
						       ],
					     -default=>"TEXT") ;
$content .= "</tr><tr><td><td><td><input type='submit' name='action' value='Add data field'>";
  $content .= "</tr></table>\n";

  $content .= $self->end_form();
 

  return $content;
}



=pod

=item * B<add_category>()

Adds a category to the ontology database

=cut

sub add_category {
  my ($self) = @_ ;


  my $cgi = $self->application->cgi;
  
  my $data = {
	      name        => $cgi->param('new_category')   || undef  ,
	      description => $cgi->param('new_description')|| undef ,
	     };

 

  # check for existing name 
  my $clist  = $self->data('ood')->Category->get_objects( $data );

  my $category = undef ;
 

  if (ref $clist and @$clist > 0){
    $category = $clist->[0] ;

    $self->app->add_message('info', "Category exists " . $category->ID );

  }
  else{
    
    # set new ID 
    $data->{ ID } = $self->data('ood')->Category->create_ID;
    print STDERR "Create new entry with ID :" .  $data->{ ID };
    print STDERR $data->{ID} . " " . $data->{name} . " " . $data->{description} ; 
    if ( defined $data->{ name } ){
      $category = $self->data('ood')->Category->create( $data );
      $self->app->add_message('info', "New category " . $category->ID );
    }
  }
 

  return $category || 0 ;
}



sub add_entry{
  my ($self) = @_;
  my $cgi        = $self->application->cgi;
  my $entry      = $cgi->param( 'new_entry') || undef ; 
  my $definition =  $cgi->param( 'entry_definition') || undef ; 
  my $node       = $self->data( 'active_node') || undef ;
  my $cat        =  $self->data('active_category') || undef ;
  my $ood        = $self->data('ood');
  my $new_id     = 1;
  my $new_node;

  unless($definition){
    $self->app->add_message('warning' , "No definition for $entry. Only terms with a dafinition will be added  to " . $self->data('active_category'));
    return 0;
  }
  my $catList = $ood->Category->get_objects( { ID => $cat } );

  if ( ref $catList and @$catList > 0 ) {
    
    
    my $category = $catList->[0];
    
    if ( $node and !(ref $node) ){
      my ($name) = $node =~/([^\:]+)$/;
      my $vars = $ood->Entry->get_objects( { name => $name } );
      $node = $vars->[0];
    }

    my $new_id = $category->ID ;

    if (ref $node){
      $new_node = $ood->Entry->create( { ID   => $new_id,
					 name => $entry,
					 category => $category,
					 parent => $node,
					 definition => $definition,
					 creator =>  $self->application->session->user,
				       } );
      
      push @{ $node->child } , $new_node;
    }
    else{
      $new_node = $ood->Entry->create( { ID   => $new_id,
					 name => $entry,
					 definition => $definition,
					 category => $category, 
					 creator =>  $self->application->session->user,
				       } );
    }
    
  }

  # no category

  else{
    
    $self->app->add_message('warning' , "Can't get " . $self->data('active_category') . " from database! " );
    
  }
  
  if (ref $new_node) {
    $self->app->add_message('info' , "Entry  " . $new_node->name . " for " . $new_node->category->name . " created ");
  }
  else{
    $self->app->add_message('warning' , "Can't add $entry  to " . $self->data('active_category'));
  }
  $cgi->param('task', 'edit') ;
  $self->data('task', 'edit') ;
}


sub delete_entry{
  my ($self) = @_;

  my $cgi    = $self->application->cgi;
  my $node   = $self->data( 'active_node') || undef ;
  my $cat    =  $self->data('active_category') || undef ;
  my $ood    = $self->data('ood');
 
  
  my $catList = $ood->Category->get_objects( { ID => $cat } );

  if ( ref $catList and @$catList > 0 ) {
    
    
    my $category = $catList->[0];
    
    if ( $node and !(ref $node) ){
      my ($name) = $node =~/([^\:]+)$/;
      my $vars = $ood->Entry->get_objects( { name => $name } );
      unless (ref $vars){
	$self->app->add_message('warning' , "no entry for $name");
	return;
      }
      if (ref $vars and scalar @$vars == 0){
	$self->app->add_message('warning' , "no entry for $name");
	return;
      }
      $self->app->add_message('warning' , "More than one entry for " . $self->data('active_node') ) if (scalar @$vars > 1);
      $node = $vars->[0];
      if (ref $node->child and scalar @{$node->child} > 0) {
	$self->app->add_message('warning' , "Can't delete ".  $self->data('active_node') . ". Delete subentries first. " ); 
      }
      else{
	$node->delete;
	$self->app->add_message('info' ,  $self->data('active_node') . " deleted" );
	$self->data('active_node' , undef );
      }
    }
    
  }

  # no category

  else{
    
    $self->app->add_message('warning' , "Can't get " . $self->data('active_category') . " from database! " );
    
  }
 
  $cgi->param('task', 'edit') ;
  $self->data('task', 'edit') ;
}



sub add_datafield{
  my ($self) = @_;

 
  my $cgi    = $self->application->cgi;
  my $entry  = $cgi->param( 'new_entry') || "none" ; 


  my $tree   = $self->application->component('OntologyTreeData');
  my $node   = $cgi->param("active_node") || "none" ;
  my $cat    = $self->data('active_category');

  my $ood    = $self->data('ood');
  my $data_name = $cgi->param('data_field_name') || "no name";
  my $data_row =  $cgi->param('data_field_row') ||  0;
  my $data_col =  $cgi->param('data_field_col') ||  0;
  my $data_type = $cgi->param('data_field_type') || 0;
 

  my $new_id = 1;
  my $new_node;

  my $catList = $ood->Category->get_objects( { ID => $cat } );

  my $category;
  my $anode;
  if ( ref $catList and @$catList > 0 ) {
    
    
    $category = $catList->[0];
    
    if ( $node and !(ref $node) ){
      my ($name) = $node =~/([^\:]+)$/;
      my $vars = $ood->Entry->get_objects( { name     => $node,
					     category => $category, } );
      unless (ref $vars){
      }
      $anode = $vars->[0];
    }
  }

  # get DataSet
  my $dataSet;
  if (ref $anode->requestedData){
    $dataSet =  $anode->requestedData;
  }
  else{
    my $id   = $ood->DataSet->create_ID;
    my $name = $category->name."|".$anode->name;
    $dataSet = $ood->DataSet->create({ name => $name,
				       ID => $id,
				     });
    
    $anode->requestedData( $dataSet);
  }

  # now create DataField
  
  my $vars = $ood->DataField->get_objects( { name     => $data_name,
					     dataSet  => $dataSet,
					     });

  if (ref $vars and scalar @$vars > 0){
    $self->app->add_message('warning' , "Can't add " . $data_name . " with type " . $data_type . " to " . $anode->name .". Data field with ".$vars->[0]->name." exists.");
    return 0;
  }
  else{
    my $position = "$data_row.$data_col";
    my $dataField = $ood->DataField->create({ name     => $data_name,
					      type     => $data_type,
					      position => $position,
					      dataSet  => $dataSet,
					    });
    
    $self->app->add_message('info' , "Data field " . $dataField->name . " crerated."); 
  }




  #$self->app->add_message('warning' , "Adding data field 1 " . $data_name . " with type " . $data_type . " to " .$anode->name );
  #$self->app->add_message('warning' , "Adding data field " . $data_name . " with type " . $data_type . " to $node");

 
 
  
}



=pod

=item * B<rget_data_fields_for_entries()

Get tree data from database and fill tree

=cut

sub get_data_fields_for_entry{
  my ($self , $data ) = @_;
  
  my $ood  = $self->data('ood');
  my $cat  = $self->data('category_object');
  my $node = $self->data('node_object');

  my $dataSet = $node->requestedData;
  
  my $content;
  my @required_fields;

  if (!ref $dataSet){
    $content .= "<p>$node for $cat</p>";
  }
  else{
    $content .= "<table><tr>";

    my $current_row = 0;
    my $dataFields = $ood->DataField->get_objects({ dataSet => $dataSet });
   
    foreach my $field (sort {$a->position <=> $b->position} @$dataFields){
      my ($row,$col) = $field->position =~ /(\d+)\.(\d+)/;
      
      unless ($current_row != $row){
        if ($current_row){
	  $content .= "</tr><tr>";
	}
	else{
	  $content .= " ";
	}
	$current_row = $row;
      }
      if (ref $data and $data->{ $field->name } ){
	$content .= "<td><a alt='".$field->type."'>" . $field->name . "</a></td><td> <input type='text' name='"."required_".$field->name."' value='".$data->{ $field->name }."'>" .  "</td>";
      }
      else{
	$content .= "<td>" . $field->name . "</td><td> <input type='text' name='"."required_".$field->name."' value=''>" .  "</td>";
      }
   
      push @required_fields , "required_".$field->name;
    }


    $content .= "</tr></table>";
  }

  $content .= "<input type='hidden' name='required_fields' value='".join "|" , @required_fields."'>";  
  return $content;
}


=pod

=item * B<rfill_ontology_tree>()

Get tree data from database and fill tree

=cut

sub fill_ontology_tree{
  my ($self, $tree , $cat , $node , $entry , $name ) = @_;
  my $ood = $self->data('ood');

  # get object for Category 
  unless(ref $cat){
    my $vars = $ood->Category->get_objects( { ID => $cat } );
    unless(ref $vars and scalar @$vars > 0){
       $self->app->add_message('warning', "No category $cat to fill tree");
    }
    $cat = $vars->[0];
  }
 

  # fill tree 
  if (ref $entry) {
    my $children = $ood->Entry->get_objects( { parent => $entry } );
    foreach my $child (@$children){
      my $child_node = $node->add_child( { 'label' => set_button_field_for_tree( $name , $child->name) } );
      $self->fill_ontology_tree( $tree , $cat , $child_node , $child , $name);
    }
  }
  elsif ($cat) {
    my $children = $ood->Entry->get_objects( { parent => undef ,
					category => $cat} );
  
    foreach my $child (@$children){
      my $node = $tree->add_node( { 'label' => set_button_field_for_tree( $name , $child->name) } );
      $self->fill_ontology_tree( $tree , $cat , $node , $child , $name );
    }
  }
 
}

sub set_scripts{
  my ($self , $target) = @_;
  my $content ='<script>';
  $content .= "function set_$target (value){
  var message = \"Active node is \" + value;

  document.getElementById(\"ManageOOD\").$target.value = value;
   document.getElementById(\"ManageOOD\").task.value = 'edit';
  document.getElementById(\"display_selection\").firstChild.nodeValue = value;
  document.getElementById(\"ManageOOD\").submit ();
  }\n";
  $content .= "</script>";
  return $content;
}



sub set_button_field_for_tree{
  my ($name , $value) = @_;
  my $button =" <a onclick=\"set_active_node('$value');\"> $value </a>";
  
  return $button;
}

=pod

=item * B<rfill_ontology_list>()

Get tree data from database and fill tree

=cut

sub fill_ontology_list{
  my ($self, $list , $cat , $entry , $labels , $values, $long_label ) = @_;
  my $ood = $self->data('ood');
  my @olist;
  
  # get object for Category 
  unless(ref $cat){
    my $vars = $ood->Category->get_objects( { name => $cat } );
    unless(ref $vars and scalar @$vars > 0){
       $self->app->add_message('warning', "No category $cat to fill list");
    }
    $cat = $vars->[0];
  }


  # fill list 
  if (ref $entry) {
    my $children = $ood->Entry->get_objects( { parent => $entry } );
    foreach my $child (@$children){
   
      my $new_label = $long_label."::".$child->name;

      push @$labels , $new_label;
      push @$values , $child->name;

      $self->fill_ontology_list( $list , $cat , $child , $labels , $values , $new_label );
    }
  }
  elsif ($cat) {
    my $children = $ood->Entry->get_objects( { parent => undef ,
					category => $cat} );
   
    foreach my $child (@$children){
     
      $long_label = $child->name;  

      push @$labels , $long_label;
      push @$values , $child->name;
      $self->fill_ontology_list( $list , $cat , $child , $labels , $values , $long_label );
    }
  }
  $list->labels( $labels );
  $list->values( $values );

}

=pod

=item * B<required_rights>()

Returns a reference to the array of required rights

=cut

sub required_rights {
  return [ [ 'login' ], ];
}
