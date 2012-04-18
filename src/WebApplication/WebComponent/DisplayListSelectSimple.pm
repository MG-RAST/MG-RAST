package WebComponent::DisplayListSelectSimple;

# DisplayListSelect - component for showing two list boxes, one that contains columns or attributes to show and the other list box shows the ones on display

# $Id: DisplayListSelect.pm

use strict;
use warnings;

use URI::Escape;

use base qw( WebComponent );

1;


=pod

=head1 NAME

    DisplayListSelect - component for showing two list boxes, one that contains columns or attributes to show and the other list box shows the ones on display

=head1 DESCRIPTION

    component for showing two list boxes, one that contains columns or attributes to show and the other list box shows the ones on display. This component has to be tied with another component (currently supports only tables, to add or remove columns from being shown);

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
 
  my $self = shift->SUPER::new(@_);
  #  my $self = shift->SUPER::new(@_);
   
  $self->{data} = undef;
  $self->{list_name} = "DisplayListSelection"; 
  $self->{form_name} = "DisplayListSelectionForm"; 
  $self->{form_new}  = 0; 

  $self->{input_header}   = '';  
  $self->{output_header}  = '';
  $self->{ajax_function}  = undef;
  $self->{selected_ids}   = undef;

  $self->{submit_name} = "displaylist_submit";		
  $self->{submit_value} = "Submit";	
  
  return $self;
}

=item * B<output> ()

Returns the html output of the DisplayListSelect component.

=cut

sub output {
    my ($self) = @_;

    # initialize variables
    my $listbox = "";

    unless ($self->data) {
	return "No column data passed to listbox creator!";
    }



    # get form variables
    
    my ($form_name , $new)   = $self->form;
    my ($iheader , $oheader) = $self->list_headers;
 
    my $cgi = $self->application->cgi;
    my ($content, %scroll_list, $out_list, $columns_to_be_shown, $linked_component, $table_id, $add_column, $hidden_content);
    my $in_list = [];
  

    my $data = $self->data;
  

    my $user = $self->application->session->user();
    
    foreach my $key (sort {lc $data->{$a} cmp lc $data->{$b}} keys %$data){
      
      push(@$out_list, $key);
      $scroll_list{$key} = $data->{$key};
      
    }
    
   
    if ($new){
      $content .= $self->start_form($form_name);
    }

    $content .= qq"<table border=0 align=center cellpadding=10><tr bgcolor=#EAEAEA><td>"; #outside table (gray colored table)
    $content .= qq"<table border=0 align=center cellpadding=0><tr<td>";
    $content .= qq"<table border=0 align=center>";
    $content .= qq"<tr><td rowspan=2>$iheader<br>";

    $content .= qq(<div class="scroll_hor">);
  
    $content .= $cgi->scrolling_list(-name => 'display_list_out'.$self->id,
                                     -id => 'display_list_out'.$self->id,
                                     -values => $out_list,
                                     -size => 5,
				     -style => 'width:250px;font-size:90%;',
                                     -labels => \%scroll_list);
#                                     -class => 'listbox',
#                                     -multiple => 'true',
#				     -style => 'width:200px;font-size:90%;',

    $content .= "</div>";
    $content .= qq"</td><td><br><br>";

    my ($onclick1, $onclick2);
  
    $onclick1 = "moveOptionsRight('display_list_out".$self->id."','".$self->list_name."')";
    $onclick2 = "moveOptionsLeft('".$self->list_name."','display_list_out".$self->id."')";
    

    $content .= $cgi->button(-name => 'add_list',
                             -class => 'btn',
                             -onClick => $onclick1,
                             -onmouseover => "hov(this,'btn btnhov')",
                             -onmouseout => "hov(this,'btn')",
                             -value => '>');

    $content .= qq"</td><td rowspan=2>$oheader<br>";
    $content .= qq(<div class="scroll_hor">);
    $content .= $cgi->scrolling_list(-name=>$self->list_name,
                                     -id => $self->list_name,
                                     -values=>$in_list,
                                     -size=>5,
				     -style => 'width:250px;font-size:90%;',
                                     -labels=>\%scroll_list,
                                     -multiple=>1,);
#                                     -class=>'listbox',
#				     -style => 'width:200px;font-size:90%;',

    $content .= "</div>";
    $content .= qq"</td></tr><tr><td>";


    $content .= $cgi->button(-name => 'remove_list',
                             -class => 'btn',
                             -onClick => $onclick2,
                             -onmouseover => "hov(this,'btn btnhov')",
                             -onmouseout => "hov(this,'btn')",
                             -value => '<');

    $content .= qq~</td></tr></table>~;
    $content .= qq~</td></tr><tr><td align='right'>~;
    $content .= qq~</td></tr></table></td></tr></table>~;
    $content .= $cgi->hidden(-name=>'_hidden_assign_from',
                             -id=>'_hidden_assign_from',
                             -value=> '');
    $content .= $cgi->hidden(-name=>'_hidden_assign_to',
                             -id=>'_hidden_assign_to',
                             -value=> '');

   
    
    #$content .= "<p><input type=\"button\" name=\"compute_table\" value=\"Compute table\" onclick='submit_selection(  \"".$form_name."\" , \"".$self->list_name."\" )'></p>\n";

    $content .= $self->get_submit_button;
   
    if ($new){
      $content .= $self->end_form();
    }

    $self->selected_ids(join ("~", @$in_list));
    return $content;
}

sub selected_ids {
    my ($self, $selected_ids) = @_;

    if (defined($selected_ids)) {
        $self->{selected_ids} = $selected_ids;
    }

    return $self->{selected_ids};
}



sub primary_ids {
    my ($self, $primary_ids) = @_;

    if (defined($primary_ids)) {
	$self->{primary_ids} = $primary_ids;
    }

    return $self->{primary_ids};
}

sub data {
    my ($self, $data) = @_;

    if (defined($data)) {
	$self->{data} = $data;
    }

    return $self->{data};
}

=item * B<list_name> ()

Getter / Setter for a  cgi parameter name. The cgi parameter
contains the selected list elements.

=cut

sub list_name {
    my ($self, $list_name) = @_;

    if (defined($list_name)) {
	$self->{list_name} = $list_name;
    }

    return $self->{list_name};
}


=item * B<form> ( form_name , new)

Getter / Setter for  form name and new  flag.
If  the  new  flag is true  a new  form  with 
"form_name" will be created for the selection 
boxes. The  existing  form  form_name will be 
used otherwise 

=cut

sub form {
    my ($self, $name , $new) = @_;

    if (defined($name)) {
	$self->{form_name} = $name;	
	$self->{form_new}  = $new if defined($new);
	
    }

    return ($self->{form_name} , $self->{form_new}) ;
}

=item * B<list_headers> ( input_list , output_list)

Setter for the list headers

=cut

sub list_headers {
    my ($self, $input , $output) = @_;

    if (defined($input)) {
	$self->{input_header} = $input;		
    }
    if (defined($output)) {
	$self->{output_header} = $output;		
    }

    return ($self->{input_header} , $self->{output_header}) ;
}

=item * B<submit_button> ( name , value)

Getter/Setter for name and value of the submit button

=cut


sub submit_button {
    my ($self, $name , $value) = @_;

    if (defined($name)) {
	$self->{submit_name} = $name;		
    }
    if (defined($value)) {
	$self->{submit_value} = $value;		
    }

    return ($self->{submit_name} , $self->{submit_value}) ;
}

=item * B<get_submit_button> ()

Returns html code for button to submit the values of the selection box

=cut

sub get_submit_button{
  my ($self) = @_;

  my ($form_name , $new)   = $self->form;
  my $list_name            = $self->list_name;
  my ($name , $value)      = $self->submit_button;
  
  my $content .= "
<p>
<input type=\"button\" name=\"".$name."_button\" value=\"".$value."\" 
onclick='submit_selection(  \"".$form_name."\" , \"".$list_name."\" , \"".$name."\" , \"".$value."\")'>
<input type=\"hidden\" name=\"".$name."\" id=\"".$name."\" value=\"\">
</p>\n";
  
  return $content;
}
sub ajax_function {
    my ($self, $ajax_function) = @_;

    if (defined($ajax_function)) {
	$self->{ajax_function} = $ajax_function;
    }

    return $self->{ajax_function};
}

sub initial_columns {
    my ($self, $initial_columns) = @_;

    if (defined($initial_columns)) {
	$self->{initial_columns} = $initial_columns;
    }

    return $self->{initial_columns};
}

sub require_javascript {
    return ['./Html/DisplayListSelectSimple.js', './Html/PopupTooltip.js'];
}

sub require_css {
    return './Html/DisplayListSelect.css';
}
