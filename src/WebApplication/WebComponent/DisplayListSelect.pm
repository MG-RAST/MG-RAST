package WebComponent::DisplayListSelect;

# DisplayListSelect - component for showing two list boxes, one that contains columns or attributes to show and the other list box shows the ones on display

# $Id: DisplayListSelect.pm

use strict;
use warnings;

use URI::Escape;
use SeedViewer::SeedViewer;
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
    $self->{linked_component} = undef;
    $self->{metadata} = undef;
    $self->{initial_columns} = undef;
    $self->{primary_ids} = [];
    $self->{ajax_function} = undef;
    $self->{new_columns} = undef;
    $self->{filter_in} = 0;
    $self->{fileter_out} = 0;

    return $self;
}

=item * B<output> ()

Returns the html output of the DisplayListSelect component.

=cut

sub output {
    my ($self) = @_;

    # initialize variables
    my $listbox = "";

    unless ($self->metadata) {
	return "No column data passed to listbox creator!";
    }

#    unless ($self->ajax_function) {
#	return "No ajax function passed associated with the listbox creator!";
#    }

#    unless ($self->linked_component) {
#	return "This listbox must be tied to a component. No component passed to listbox creator!";
#    }

#    unless ($self->primary_ids) {
#	return "This listbox must be tied to a set of ids. These are the ids that the columns will get the information for.";
#    }

    # get form variables
    my $cgi = $self->application->cgi;
    my ($content, %scroll_list, $out_list, $columns_to_be_shown, $linked_component, $table_id, $add_column, $hidden_content);
    my $in_list = [];
    if ($self->linked_component){
	$linked_component = $self->linked_component;
	$table_id = $linked_component->id();
	$add_column = $self->ajax_function;
	
	# Introduce the sims table
	$hidden_content .= $cgi->hidden(-name=>'simtable_id',
					-value=> $table_id);
    }

    my $columns_metadata = $self->metadata;
    my $primary_ids = $self->primary_ids if (defined $self->primary_ids);

    my $user = $self->application->session->user();
    
    foreach my $key (sort {lc $columns_metadata->{$a}->{value} cmp lc $columns_metadata->{$b}->{value}} keys %$columns_metadata){
        my $keyname;
        my $order;
        if ( (defined ($cgi->param('col_id~' . $key))) && ($cgi->param('col_id~' . $key) >= 0)  ){
            $order = $cgi->param('col_id~' . $key);
        }
        else{
            $order = $columns_metadata->{$key}->{order};
        }

	# determine in which list box the attribute should be at
        if ( ( ($order) && ($columns_metadata->{$key}->{visible} == 1) ) ||
             ( (defined ($cgi->param('column~' . $key))) && ($cgi->param('column~' . $key) == 1) )||
             ( (defined ($cgi->param('col_id~' . $key))) && ($cgi->param('col_id~' . $key) >= 0) ) ){  # if the columns should be visible
            $keyname = $key;
            my $visible = 1;
            $visible = $cgi->param('column~' . $key) if (defined $cgi->param('column~' . $key) );
            if (defined $cgi->param('column~' . $key)){
                $columns_metadata->{$key}->{visible} = $cgi->param('column~' . $key);
                $columns_metadata->{$key}->{order} = $cgi->param('col_id~' . $key) + 1 if ($cgi->param('col_id~' . $key));
            }
            else{
                $columns_metadata->{$key}->{visible} = 1;
            }
            $hidden_content .= $cgi->hidden(-name=> 'col_id~' . $key, -id=> 'col_id~'. $key, -value=> $order-1) if ($order);
            $hidden_content .= $cgi->hidden(-name => 'column~' . $key, -id => 'column~' . $key, -default => $visible);
	    if ($columns_metadata->{$key}->{group} ne "permanent"){
		push(@$in_list, $key);
	    }
        }
	elsif ( ($order) 
		&& ($columns_metadata->{$key}->{visible} == 0) 
		&& $user && (user_can_annotate_genome($self->application)) 
		&& ($columns_metadata->{$key}->{group} eq 'permanent') ){
            # if it should be visible when certain users log in
            $keyname = $key;
            $columns_metadata->{$key}->{visible} = 1;
            $hidden_content .= $cgi->hidden(-name=> 'col_id~' . $key, -id=> 'col_id~' . $key, -value=> $order-1);
            $hidden_content .= $cgi->hidden(-name => 'column~' . $key, -id => 'column~' . $key, -default => 1);
	    if ($columns_metadata->{$key}->{group} ne "permanent"){
		push(@$in_list, $key);
	    }
        }
	elsif ( ($order) && ($columns_metadata->{$key}->{visible} == 0) && (!$user) ){
	    $keyname = $key;
	    $hidden_content .= $cgi->hidden(-name=> 'col_id~' . $key, -id=> 'col_id~' . $key, -value=> $order-1);
	    $hidden_content .= $cgi->hidden(-name => 'column~' . $key, -id => 'column~' . $key, -default => 0);
	    #push(@$out_list, $key);
	}
        elsif (!$order){   # non visible columns
            $keyname = $key;
            $hidden_content .= $cgi->hidden(-name=> 'col_id~' . $key, -id=> 'col_id~' . $key, -value=> -1);
            $hidden_content .= $cgi->hidden(-name => 'column~' . $key, -id => 'column~' . $key, -default => 0);
            push(@$out_list, $key);
        }
        if ($keyname){
            $scroll_list{$key} = $columns_metadata->{$key}->{value};
            if (( ($columns_metadata->{$key}->{visible} == 1) 
		  || ( (defined ($cgi->param('col_id~' . $key))) && ($cgi->param('col_id~' . $key) >= 0) ) ) 
		&& ($self->linked_component)  || (($columns_metadata->{$key}->{visible} == 0) && ($order)) ){
		if (ref($columns_metadata->{$key}->{header}) eq 'HASH'){
		    $columns_to_be_shown->[$columns_metadata->{$key}->{order} - 1] = {'key' => $key,
                                                                                      'visible' => $columns_metadata->{$key}->{visible}
                                                                                  };
		    foreach my $subkey (keys %{$columns_metadata->{$key}->{header}}){
			#print STDERR "KEY: " .  $subkey . "\n";
			$columns_to_be_shown->[$columns_metadata->{$key}->{order} - 1]->{$subkey} = $columns_metadata->{$key}->{header}->{$subkey};
		    }
		}
		else{
		    $columns_to_be_shown->[$columns_metadata->{$key}->{order} - 1] = {'key' => $key, 
										      'name' => $columns_metadata->{$key}->{header}, 
										      'visible' => $columns_metadata->{$key}->{visible}
										  };
		}
	    }
	}
    }
    
    if ($self->linked_component){
	$hidden_content .= $cgi->hidden(-name=> $table_id . '_column_qty', -id => $table_id .'_column_qty', -value => scalar(@$columns_to_be_shown));
    }
    else {
	$hidden_content .= $cgi->hidden(-name=>'new_columns',
					-id => 'new_columns',
					-value => join("~", @$in_list));
    }

    my @scroll_array;
    foreach my $out (@$out_list){
      push @scroll_array, $scroll_list{$out};
    }

    $content .= qq"<table border=0 align=center cellpadding=10><tr bgcolor=#EAEAEA><td>"; #outside table (gray colored table)
    $content .= qq"<table border=0 align=center cellpadding=0><tr<td>";
    $content .= qq"<table border=0 align=center>";
    $content .= qq"<tr><td rowspan=2>Columns not in display:<br>";
    $content .= $hidden_content;
    my ($filter_out_id, $filter_select_out_id, $filter_select_in_id);

    if ($self->filter_out){
	$self->application->register_component('FilterSelect', 'FilterSelectOut');

	my $filter_select_component = $self->application->component('FilterSelectOut');
	$filter_select_component->labels(  \@scroll_array );
	$filter_select_component->values( $out_list );
	$filter_select_component->size(5);
	$filter_select_component->width(250);
	$filter_select_component->name('sim_display_list_out');
	$content .= $filter_select_component->output();

#	$filter_out_id = "filter_select_" . $filter_select_component->id();
	$filter_out_id = $filter_select_component->id();
	$filter_select_out_id = "filter_select_" . $filter_select_component->id();
	$filter_select_in_id = "filter_select_" . ($filter_select_component->id()+1);
    }
    else{
	$content .= qq(<div class="scroll_hor">);
	$content .= $cgi->scrolling_list(-name => 'sim_display_list_out',
					 -id => 'filter_select_1000',
					 -values => $out_list,
					 -size => 6,
					 -style => 'width:250px;font-size:90%;',
					 -labels => \%scroll_list);
	
	$content .= "</div>";
#	$filter_out_id = "filter_select_1000";
	$filter_out_id = 1000;
	$filter_select_out_id ="filter_select_1000";
	$filter_select_in_id = "filter_select_1001";
    }
    $content .= qq"</td><td><br><br>";

    my ($onclick1, $onclick2);
    if ($self->linked_component){
	$onclick1 = "moveOptionsRight('$filter_select_out_id','$filter_select_in_id','$table_id','$add_column')";
	$onclick2 = "moveOptionsLeft('$filter_select_in_id','$filter_select_out_id','$table_id')";
    }
    else{
	$onclick1 = "moveOptionsRight('$filter_select_out_id','$filter_select_in_id')";
	$onclick2 = "moveOptionsLeft('$filter_select_in_id','$filter_select_out_id')";
    }

    $content .= $cgi->button(-name => 'add_list',
                             -class => 'btn',
                             -onClick => $onclick1,
                             -onmouseover => "hov(this,'btn btnhov')",
                             -onmouseout => "hov(this,'btn')",
                             -value => '>');

    $content .= qq"</td><td rowspan=2>Columns in display:<br>";
    if ($self->filter_in){
	$self->application->register_component('FilterSelect', 'FilterSelectIn');

	my $filter_select_component = $self->application->component('FilterSelectIn');
	$filter_select_component->labels(  \@scroll_array );
	$filter_select_component->values( $in_list );
	$filter_select_component->size(8);
	$filter_select_component->width(250);
	$filter_select_component->name('sim_display_list_in');
	$content .= $filter_select_component->output();
    }
    else{
	$content .= qq(<div class="scroll_hor">);
	$content .= $cgi->scrolling_list(-name=>'sim_display_list_in',
					 -id => $filter_select_in_id,
					 -values=>$in_list,
					 -size=>6,
					 -style => 'width:250px;font-size:90%;',
					 -labels=>\%scroll_list);
	
	$content .= "</div>";
    }
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

    if (defined $self->primary_ids){
	my $value = join ("~", @$primary_ids);
	$content .= $cgi->hidden(-name=>'primary_ids', -id => 'primary_ids', -value => $value);
    }
    
    $self->initial_columns($columns_to_be_shown);
    $self->new_columns(join ("~", @$in_list));
    return $content;
}

sub new_columns {
    my ($self, $new_columns) = @_;

    if (defined($new_columns)) {
        $self->{new_columns} = $new_columns;
    }

    return $self->{new_columns};
}

sub linked_component {
    my ($self, $linked_component) = @_;

    if (defined($linked_component)) {
	$self->{linked_component} = $linked_component;
    }

    return $self->{linked_component};
}

sub primary_ids {
    my ($self, $primary_ids) = @_;

    if (defined($primary_ids)) {
	$self->{primary_ids} = $primary_ids;
    }

    return $self->{primary_ids};
}

sub filter_in {
    my ($self, $filter_in) = @_;

    if (defined($filter_in)) {
	$self->{filter_in} = $filter_in;
    }

    return $self->{filter_in};
}

sub filter_out {
    my ($self, $filter_out) = @_;

    if (defined($filter_out)) {
	$self->{filter_out} = $filter_out;
    }

    return $self->{filter_out};
}

sub metadata {
    my ($self, $metadata) = @_;

    if (defined($metadata)) {
	$self->{metadata} = $metadata;
    }

    return $self->{metadata};
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
    return ["$Conf::cgi_url/Html/DisplayListSelect.js", "$Conf::cgi_url/Html/PopupTooltip.js"];
}

sub require_css {
    return "$Conf::cgi_url/Html/DisplayListSelect.css";
}
