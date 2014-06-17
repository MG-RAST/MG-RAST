package WebComponent::Table;

# Table - component for all kinds of tables

# $Id: Table.pm,v 1.70 2011-11-14 13:02:02 paczian Exp $

use strict;
use warnings;

use URI::Escape;
use Data::Dumper;
use File::Temp qw/ tempfile tempdir /;

use Conf;

use base qw( WebComponent );

1;


=pod

=head1 NAME

Table - component for all kinds of tables

=head1 DESCRIPTION

WebComponent for all kinds of tables

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{data} = undef;
  $self->{supercolumns} = [];
  $self->{columns} = undef;
  $self->{items_per_page} = -1;
  $self->{show_select_items_per_page} = 0;
  $self->{show_top_browse} = 0;
  $self->{show_bottom_browse} = 0;
  $self->{show_export_button} = 0;
  $self->{show_clear_filter_button} = 0;	
  $self->{offset} = 0;
  $self->{width} = -1;
  $self->{visible_columns} = [];
  $self->{control_panel} = [];
  $self->{enable_upload} = 0;
  $self->{show_column_select} = 0;
  $self->{column_select_toggle} = 1;
  $self->{preferences_key} = 0;
  $self->{dynamic_data} = 0;
  $self->{other_buttons} = [];
  $self->{sequential_init} = 0;

  # register hover component
  $self->application->register_component('Hover', 'TableHoverComponent'.$self->id());
  $self->application->register_component('Ajax', 'TableAjaxComponent'.$self->id());

  return $self;
}

=item * B<output> ()

Returns the html output of the Table component.

=cut

sub output {
  my ($self) = @_;
  # initialize variables
  my $table = "";

  $table .= "<input type='hidden' id='" . $self->{_id} . "' value='" . $self->id() . "' />";

  unless ($self->data) {
    unless ($self->dynamic_data()) {
      return "No data passed to table creator!";
    }
  }
  unless ($self->columns) {
    return "No columns passed to table creator!";
  }

  # get the hover component
  my $hover_component = $self->application->component('TableHoverComponent'.$self->id());

  # calculate the number of rowse
  my $total;
  if ($self->data()) {
    $total = scalar(@{$self->data});
  } else {
    $total = 0;
  }


  # set the image path
  my $img_path = "$Conf::cgi_url/Html/";

  # format the data into strings
  my ($data_source, $onclicks, $highlights) = $self->format_data();

  # check the column types
  my $column_types = [];
  foreach my $col (@{$self->columns}) {
    if (ref($col)) {
      if ($col->{input_type} && $col->{input_type} eq 'select') {
	$col->{input_type} = join('@#', @{$col->{select_options}});
      }
      push(@$column_types, $col->{input_type} || '');
    }
  }
  $column_types = join('@~', @$column_types);
  # hidden storage variables
  $table .= "\n<input type='hidden' id='table_data_" . $self->id() . "' value='" . $data_source . "'>\n";
  $table .= "<input type='hidden' id='table_onclicks_" . $self->id() . "' value='" . $onclicks . "'>\n";
  $table .= "<input type='hidden' id='table_highlights_" . $self->id() . "' value='" . $highlights . "'>\n";
  $table .= "<input type='hidden' id='table_filtereddata_" . $self->id() . "' value=''>\n";
  $table .= "<input type='hidden' id='table_rows_" . $self->id() . "' value='" .  $total . "'>\n";
  $table .= "<input type='hidden' id='table_cols_" . $self->id() . "' value='" . scalar(@{$self->columns}) . "'>\n";
  $table .= "<input type='hidden' id='table_start_" . $self->id() . "' value='" . $self->offset() . "'>\n";
  $table .= "<input type='hidden' id='table_sortdirection_" . $self->id() . "' value='up'>\n";
  $table .= "<input type='hidden' id='table_column_types_" . $self->id() . "' value='" . $column_types . "'>\n";
  $table .= "<input type='hidden' id='table_hoverid_" . $self->id() . "' value='" . $hover_component->id . "'>\n";
  $table .= "<span id='table_input_space_" . $self->id() . "'></span>";

  # check if we want to enable upload
  my $ajax = $self->application->component('TableAjaxComponent'.$self->id());
  $table .= $ajax->output();
  if ($self->enable_upload) {
    $table .= "<div style='display: none;' id='table_".$self->id()."_ajax_target'></div>";
  }

  # check for export button
  my $export_button = "";
  if (ref($self->show_export_button())) {
    my $exphash = $self->show_export_button();
    if (ref($exphash) eq 'ARRAY') {
      foreach my $exph (@$exphash) {
	my $title = $exph->{title} || 'export table';
	my $unfiltered = $exph->{unfiltered} || 0;
	my $strip_html = $exph->{strip_html} || 0;
	my $hide_invisible_columns = $exph->{hide_invisible_columns} || 0;
	$export_button .= "<input type='button' class='button' value='$title' onclick='export_table(\"" . $self->id() . "\", $unfiltered, $strip_html, $hide_invisible_columns);'>";
      }
    } else {
      my $title = $exphash->{title} || 'export table';
      my $unfiltered = $exphash->{unfiltered} || 0;
      my $strip_html = $exphash->{strip_html} || 0;
      my $hide_invisible_columns = $exphash->{hide_invisible_columns} || 0;
      $export_button .= "<input type='button' class='button' value='$title' onclick='export_table(\"" . $self->id() . "\", $unfiltered, $strip_html, $hide_invisible_columns);'>";
    }
  } elsif ($self->show_export_button()) {
    $export_button .= "<input type='button' class='button' value='export table' onclick='export_table(\"" . $self->id() . "\");'>";
  }
  $table .= "<div style='display:none;' id='table_".$self->id()."_download'></div>";
  
  # check for clear filter button
  my $clear_filter_button = "";
  if ($self->show_clear_filter_button()) {
    $clear_filter_button = "<input type='button' class='button' value='clear all filters' onclick='table_reset_filters(\"" . $self->id() . "\");'>";
  }

  my $buttons = $self->other_buttons;
  if ($export_button)       { push @$buttons, $export_button; }
  if ($clear_filter_button) { push @$buttons, $clear_filter_button; }
  my $button_row = (@$buttons > 0) ? "<tr><td>" . join("&nbsp;&nbsp;", @$buttons) . "</td></tr>" : "";

  my $table_width = "";
  if ($self->width() ne '-1') { $table_width = "width: " . $self->width() . "px;"; }

  my $select_items_per_page = "";
  if ($self->show_select_items_per_page) {
    if ($self->items_per_page() == -1) {
      $self->items_per_page(scalar(@{$self->data}));
    }
    $select_items_per_page .= "<tr><td style='width: 100%; text-align: center; vertical-align: middle;'><table style='width: 100%;'>\n<tr><td align=center><span class='table_perpage'>display&nbsp;<input type='text' id='table_perpage_" . $self->id() . "' name='table_perpage_" . $self->id() . "' size='3' value='" . $self->items_per_page() . "' onkeypress='return check_submit_filter(event, \"" . $self->id() . "\");'>&nbsp;items per page</span></td></tr></table></td></tr>\n";
  } elsif ($self->items_per_page < 0) {
     $select_items_per_page .= "<input type='hidden' id='table_perpage_" . $self->id() . "' name='table_perpage_" . $self->id() . "' value='" . ($self->data ? scalar(@{$self->data}) : 0) . "' >\n";
  } else {
     $select_items_per_page .= "<input type='hidden' id='table_perpage_" . $self->id() . "' name='table_perpage_" . $self->id() . "' value='" . $self->items_per_page() . "' >\n";
  }
  
  # check for display options - display browse element at the top and bottom
  my $topbrowse = "";
  if ($self->show_top_browse) {
    $topbrowse = "<tr><td style='width: 100%; text-align: center;'>".$self->get_browse()."</td></tr>";
  }
  my $bottombrowse = "";
  if ($self->show_bottom_browse) {
    $bottombrowse = "<tr><td style='width: 100%; text-align: center;'>".$self->get_browse('bottom')."</td></tr>";  
  }
  
  $table .= "<table id='table_" . $self->id() . "' class='table_table' style='$table_width'>";

  # check for supercolumns
  my $supercolumns = "";
  if (scalar(@{$self->supercolumns})) {
    $table .= "<tr id='table_".$self->id."_supercolumns'>";
    my $n = 0;
    foreach my $sc (@{$self->supercolumns}) {
      $table .= "<td class='table_first_row' id='table_sc_" . $self->id() . "_".$n."' colspan='".$sc->[1]."' style='text-align: center;'>".$sc->[0]."</td>";
      $supercolumns .= $n."~".$sc->[1]."^";
      $n++;
    }
    $table .= "</tr>";
  }
  chop $supercolumns;

  $table .= "<tr>";
  my $i = 1;

  my $vis_cols = 0;
  if ($self->preferences_key) {
    if ($self->application->session->user) {
      my $prefs = $self->application->dbmaster->Preferences->get_objects( { user => $self->application->session->user,
									    name => 'table_pref_'.$self->preferences_key } );
      if (scalar(@$prefs)) {
	$vis_cols = $prefs->[0]->value;
	my @vis_cols_array = split(/@~/, $vis_cols);
	my $vi = 0;
	foreach my $col (@{$self->columns}) {
	  unless (ref($col)) {
	    $col = { name => $col };
	  }
	  if ($vi < scalar(@vis_cols_array)) {
	    $col->{visible} = $vis_cols_array[$vi];
	  } else {
	    $col->{visible} = 1;
	  }
	  $vi++;
	}
      }
    }
  }

  my $combo_columns = [];
  foreach my $col (@{$self->columns}) {
    unless (ref($col)) {
      $col = { name => $col };
    }

    # check for visible columns
    if (exists($col->{show_control}) && $col->{show_control}) {
      $col->{visible} = -1;
    }
    if (exists($col->{visible})) {
      push(@{$self->{visible_columns}}, $col->{visible});
    } else {
      $col->{visible} = 1;
      push(@{$self->{visible_columns}}, 1);
    }
    
    my $col_id = $self->id() . "_col_" . $i;

    my $tooltip = "";
    my $menu = "";
    if (exists($col->{tooltip})) {
      $tooltip = "onmouseover='hover(event, \"$col_id\", \"".$hover_component->id()."\");' ";
      $hover_component->add_tooltip($col_id, $col->{tooltip});
    }
    if (exists($col->{menu})) {
      $menu = "onclick='hover(event, \"$col_id\", \"".$hover_component->id()."\");' ";
      $hover_component->add_menu($col_id, $col->{menu}->{titles}, $col->{menu}->{links});
    }

    if (exists($col->{width})) {
      $col->{width} = "width: " . $col->{width} . "px;";
    } else {
      $col->{width} = "";
    }

    if (exists($col->{maxwidth})) {
      $col->{maxwidth} = "max-width: " . $col->{maxwidth} . "px;";
    } else {
      $col->{maxwidth} = "";
    }
    
    unless (exists($col->{sortable})) {
      $col->{sortable} = 0;
    }

    my $name = $self->id() . "_col_" . $i;

    my $filter = "";
    if (exists($col->{filter}) && $col->{filter} == 1) {
      my $operand = "";
      if (defined($col->{operand})) {
	$operand = $col->{operand};
      }
      if (exists($col->{operators})) {
	$filter = "<br><select name='" . $name . "_operator' id='table_" . $self->id() . "_operator_" . $i . "' style='width: 40px;' onchange='check_default_selection(this);'>";
	
	foreach my $operator (@{$col->{operators}}) {
	  my $selected = "";
	  if (defined($col->{operator}) && $col->{operator} eq $operator) {
	    $selected = " selected=selected";
	  }
	  my $operator_symbol = "invalid operator";
	  if ($operator eq 'like') {
	    $operator_symbol = '&cong;';
	  } elsif ($operator eq 'unlike') {
	    $operator_symbol = '!&cong;';
	  } elsif ($operator eq 'equal') {
	    $operator_symbol = '=';
	  } elsif ($operator eq 'unequal') {
	    $operator_symbol = '!=';
	  } elsif ($operator eq 'less') {
	    $operator_symbol = '&lt;';
	  } elsif ($operator eq 'more') {
	    $operator_symbol = '&gt;';
	  }

	  $filter .= "<option value='" . $operator . "'$selected>" . $operator_symbol . "</option>";
	}
	$filter .= "</select><input type='text' name='" . $name . "' class='filter_item' value='" . $operand . "' id='table_" . $self->id() . "_operand_" . $i . "' onkeypress='return check_submit_filter(event, \"" . $self->id() . "\");' style='width: 60%;'>";
      } elsif (defined($col->{operator}) && ($col->{operator} eq 'combobox')) {
	push(@$combo_columns, $i);
	my %coldata = map { $_->[$i - 1] => 1 } @{$self->data()};
	$filter = "<br><input type=hidden name='" . $name . "_operator' value='equal' id='table_" . $self->id() . "_operator_" . $i . "'><select name='" . $name . "' class='filter_item' id='table_" . $self->id() . "_operand_" . $i . "' onchange='return check_submit_filter2(\"" . $self->id() . "\", this.options[this.selectedIndex].text);' style='width: 100%;' title='Select Filter'>";
 	$filter .= "</select>";
      } elsif (defined($col->{operator}) && ($col->{operator} eq 'combobox_plus')) {
	push(@$combo_columns, $i);
	my %coldata = map { $_->[$i - 1] => 1 } @{$self->data()};
	$filter = "<br><select name='" . $name . "_operator' id='table_" . $self->id() . "_operator_" . $i . "' style='width: 40px;' onchange='return check_submit_filter2(\"" . $self->id() . "\");'><option value='equal' selected=selected>=</option><option value='unequal'>!=</option></select><select name='" . $name . "' class='filter_item' id='table_" . $self->id() . "_operand_" . $i . "' onchange='return check_submit_filter2(\"" . $self->id() . "\", this.options[this.selectedIndex].text);' style='width: 100%;' title='Select Filter'>";
 	$filter .= "</select>";
      } elsif (defined($col->{operator}) && ($col->{operator} eq 'all_or_nothing')) {
	$filter = "<br><select name='" . $name . "_operator' id='table_" . $self->id() . "_operator_" . $i . "' style='width: 45px;' onchange='check_default_selection(this); check_submit_filter2(\"" . $self->id() . "\");'><option value='' selected=selected>All</option><option value='empty'>empty</option><option value='notempty'>non-empty</option></select><input type='hidden' name='" . $name . "' id='table_" . $self->id() . "_operand_" . $i . "' value='x'>";
      } else {
	my $operator = 'like';
	if (defined($col->{operator})) {
	  $operator = $col->{operator};
	}
	$filter = "<br><input type=hidden name='" . $name . "_operator' value='" . $operator . "' id='table_" . $self->id() . "_operator_" . $i . "'>";

	my $ftype = 'text';
	if ($col->{hide_filter}) {
	  $ftype = 'hidden';
	}
	$filter .= "<input type='$ftype' name='" . $name . "' class='filter_item' value='" . $operand . "' size=5 id='table_" . $self->id() . "_operand_" . $i . "' onkeypress='return check_submit_filter(event, \"" . $self->id() . "\");' style='width: 100%;' title='Enter Search Text'>";
      }
    }

    # make colname referencable by js
    $col->{name_only} = $col->{name};
    $col->{name} = "<span id='colname_$col_id'>".$col->{name}."</span>";

    # check if colum header click should sort
    if ($col->{sortable}) {
      $col->{name} = "<a href='javascript: table_sort(\"" . $self->id() . "\", \"" . $i . "\");' class='table_first_row' title='click to sort'>" . $col->{name} . "&nbsp;<img src=\"./Html/up-arrow.gif\"><img src=\"./Html/down-arrow.gif\"></a>";
    }

    # check whether this column goes to the control panel
    if ($col->{visible} == 1) {
      $table .= "<td name='$name' id='$col_id' " . $tooltip . $menu . "class='table_first_row' style='" . $col->{width} . $col->{maxwidth} . "'>" . $col->{name} . $filter . "</td>";
    } elsif ($col->{visible} == -1) {
      $filter =~ s/<br>//g;
      push(@{$self->{control_panel}}, "<td name='$name' id='$col_id' class='table_first_row'" . $tooltip . $menu . " style='" . $col->{width} . $col->{maxwidth} . "'>" . $col->{name} . "</td><td>" . $filter . "</td>");
    } else {
      $table .= "<td name='$name' id='$col_id' " . $tooltip . $menu . "class='table_first_row' style='" . $col->{width} . $col->{maxwidth} . "; display: none;'>" . $col->{name} . $filter . "</td>";      
    }

    # increase column counter
    $i ++;
  }

  # insert column visibility control
  if ($self->show_column_select) {
    $table .= "<td class='table_first_row' title='show / hide columns'><div onclick='if (document.getElementById(\"tscs" . $self->id . "\").style.display == \"inline\") { document.getElementById(\"tscs" . $self->id . "\").style.display = \"none\"; } else { document.getElementById(\"tscs" . $self->id . "\").style.display = \"inline\"; }' style='cursor: pointer;'>...</div><div id='tscs" . $self->id . "' style='display: none; position: absolute; border: 1px solid black; margin-left: -3px; margin-top: 2px; background-color: white;'>";
    $table .= "<table style='color: black;'>";
    my $cind = 0;
    foreach my $col (@{$self->columns}) {
      unless (ref($col)) {
	$col = { name => $col };
      }
      my $vis = 1;
      if($col->{name} =~ /input type\=\"checkbox\"/) {
        $cind++;
        next;
      }
      if ($col->{unaddable}) {
	$cind++;
	next;
      }
      if (exists($col->{visible}) && ! $col->{visible}) {
	$vis = 0;
      }
      if ($vis) {
	$vis = '<div id="tcsel'.$self->id.'_'.$cind.'" style="border: 1px inset black; width: 10px; height: 12px; margin-top: 1px; padding-left: 2px;">x</div>';
      } else {
	$vis = '<div id="tcsel'.$self->id.'_'.$cind.'" style="border: 1px inset black; width: 10px; height: 12px; margin-top: 1px; padding-left: 2px;">&nbsp;</div>';
      }
      if ($self->column_select_toggle) {
	$table .= "<tr style='cursor: pointer;' onclick='if (document.getElementById(\"tcsel".$self->id."_".$cind."\").innerHTML.length > 1) { document.getElementById(\"tcsel".$self->id."_".$cind."\").innerHTML = \"&times;\"; show_column(\"" . $self->id . "\", \"" . $cind . "\"); } else { document.getElementById(\"tcsel".$self->id."_".$cind."\").innerHTML = \"&nbsp;\"; hide_column(\"" . $self->id . "\", \"" . $cind . "\"); }; document.getElementById(\"tscs" . $self->id . "\").style.display = \"none\";'><td style='font-weight: bold;'>$vis</td><td>".$col->{name_only}."</td></tr>";
      } else {
	$table .= "<tr style='cursor: pointer;' onclick='if (document.getElementById(\"tcsel".$self->id."_".$cind."\").innerHTML.length > 1) { document.getElementById(\"tcsel".$self->id."_".$cind."\").innerHTML = \"&times;\"; } else { document.getElementById(\"tcsel".$self->id."_".$cind."\").innerHTML = \"&nbsp;\"; };'><td style='font-weight: bold;'>$vis</td><td>".$col->{name_only}."</td></tr>";
      }
      $cind++;
    }
    $table .= "</table>";
    if ($self->preferences_key && $self->application->session->user) {
      $table .= qq~<span id='tcvisstatus~ . $self->id . qq~'></span><input type='button' value='save settings' onclick="execute_ajax('set_visible_column_preferences', 'tcvisstatus~ . $self->id . qq~', 'pref_key=~ . $self->preferences_key . qq~&pref_setting='+get_visibility_string('~ . $self->id . qq~'),'saving', 0, null,'Table|~ . $self->{_id} . qq~');">~;
    }
    if (! $self->column_select_toggle) {
      $table .= "<input type='button' value='apply' onclick='apply_column_select(\"".$self->id."\");'>";
    }
    $table .= "</div></td></tr>";
  }

  # end data table
  $table .= "</table>";

  # check if we have preferences enabled
  unless ($vis_cols) {
    $vis_cols = join('@~', @{$self->{visible_columns}});
  }

  # include visible_columns information
  $table .= "<input type='hidden' id='table_visible_columns_" . $self->id() . "' value='" . $vis_cols . "'>\n";

  # include combobox location information
  $table .= "<input type='hidden' id='table_combo_columns_" . $self->id() . "' value='" . join('@~', @$combo_columns) . "'>\n";

  # include supercolumn information
  $table .= "<input type='hidden' id='table_sc_" . $self->id() . "' value='$supercolumns'>";

  # include image for table initialization unless dynamic
  unless ($self->dynamic_data()) {
    if ($self->sequential_init()) {
      push(@{$self->application->js_init_functions()}, "initialize_table('" . $self->id() . "');");
    } else {
      $table .= "<img src='" . $img_path . "clear.gif' onload='initialize_table(\"" . $self->id() . "\")'>";
    }
  }

  # print tooltips
  $table .= $hover_component->output();

  # check for control panel
  my $control_panel = "";
  if (scalar(@{$self->{control_panel}})) {
    $control_panel = "<tr><td><table>";
    my $i = 0;
    foreach my $control (@{$self->{control_panel}}) {
      if ($i % 2) {
	$control_panel .= $control . "</tr>";
      }	else {
	$control_panel .= "<tr>".$control;
      }
      $i++;
    }
    unless ($control_panel =~ /\<\/tr\>$/) {
      $control_panel .= "</tr>";
    }

    $control_panel .= "</table></td></tr>";
  }

  $table = "<table class='table_table'>".$button_row.$select_items_per_page.$topbrowse.$control_panel."<tr><td>".$table."</td></tr>".$bottombrowse."</table>";

  return $table;
}

# get the browsing html
sub get_browse {
  my ($self, $top) = @_;

  unless ($top) {
    $top = "top";
  }

  my $left = "<a href='javascript: table_first(\"" . $self->id() . "\");' name='table_first_" . $self->id() . "'>&laquo;first</a>&nbsp;&nbsp;<a href='javascript: table_prev(\"" . $self->id() . "\");' name='table_prev_" . $self->id() . "'>&laquo;prev</a>";

  my $right = "<a href='javascript: table_next(\"" . $self->id() . "\");' name='table_next_" . $self->id() . "'>next&raquo;</a>&nbsp;&nbsp;<a href='javascript: table_last(\"" . $self->id() . "\");' name='table_last_" . $self->id() . "'>last&raquo;</a>";

  my $to;
  if ($self->data()) {
    $to = scalar(@{$self->data});
  } else {
    $to = 0;
  }

  my $browse .= "<table style='width: 100%;'><tr><td align='left' width='20%'>" . $left . "</td><td align='center' width='60%'>displaying <span id='table_start_$top\_" . $self->id() . "'>" . ($self->offset() + 1) . "</span> - <span id='table_stop_$top\_" . $self->id() . "'>" . $to . "</span> of <span id='table_total_$top\_" . $self->id() . "'>" . $to . "</span></td><td align='right' width='20%'>" . $right . "</td></tr></table>";
  
  return $browse;
}

# returns a submit button which will make sure all the input columns are included in the form
sub submit_button {
  my ($self, $params) = @_;

  unless (defined($params)) {
    $params = {};
  }

  my $form_name = $params->{form_name};
  my $button_name = $params->{button_name};
  my $filter_export = $params->{filter_export};
  my $submit_all = $params->{submit_all};

  unless (defined($form_name)) {
    return "no form name given";
  }

  unless (defined($button_name)) {
    $button_name = "Submit";
  }

  unless (defined($filter_export)) {
    $filter_export = 0;
  }

  unless (defined($submit_all)) {
    $submit_all = 1;
  }

  my $html = "<input type='button' class='button' value='$button_name' onclick='table_submit(\"" . $self->id() . "\", \"$form_name\", \"$submit_all\", 0, \"$button_name\");'>";

  return $html;
}

sub data {
  my ($self, $data) = @_;

  if (defined($data)) {
    $self->{data} = $data;
  }

  return $self->{data};
}

sub columns {
  my ($self, $columns) = @_;

  if (defined($columns)) {
    $self->{columns} = $columns;
  }

  return $self->{columns};
}

sub items_per_page {
  my ($self, $items_per_page) = @_;

  if (defined($items_per_page)) {
    $self->{items_per_page} = $items_per_page;
  }

  return $self->{items_per_page};
}

sub show_export_button {
  my ($self, $show_export_button) = @_;

  if (defined($show_export_button)) {
    $self->{show_export_button} = $show_export_button;
  }

  return $self->{show_export_button};
}

sub show_clear_filter_button {
  my ($self, $show_clear_filter_button) = @_;

  if (defined($show_clear_filter_button)) {
    $self->{show_clear_filter_button} = $show_clear_filter_button;
  }

  return $self->{show_clear_filter_button};
}

sub show_select_items_per_page {
  my ($self, $show_select_items_per_page) = @_;

  if (defined($show_select_items_per_page)) {
    $self->{show_select_items_per_page} = $show_select_items_per_page;
  }

  return $self->{show_select_items_per_page};
}

sub show_top_browse {
  my ($self, $show_top_browse) = @_;

  if (defined($show_top_browse)) {
    $self->{show_top_browse} = $show_top_browse;
  }

  return $self->{show_top_browse};
}

sub show_bottom_browse {
  my ($self, $show_bottom_browse) = @_;

  if (defined($show_bottom_browse)) {
    $self->{show_bottom_browse} = $show_bottom_browse;
  }

  return $self->{show_bottom_browse};
}

sub show_control_panel {
  my ($self, $show_control_panel) = @_;

  if (defined($show_control_panel)) {
    $self->{show_control_panel} = $show_control_panel;
  }

  return $self->{show_control_panel};
}

sub offset {
  my ($self, $offset) = @_;

  if (defined($offset)) {
    $self->{offset} = $offset;
  }

  return $self->{offset};
}

sub width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{width} = $width;
  }

  return $self->{width};
}

sub enable_upload {
  my ($self, $enable) = @_;

  if (defined($enable)) {
    $self->{enable_upload} = $enable;
  }

  return $self->{enable_upload};
}

sub supercolumns {
  my ($self, $supercolumns) = @_;

  if (defined($supercolumns)) {
    $self->{supercolumns} = $supercolumns;
  }

  return $self->{supercolumns};
}

sub ajax_target {
  my ($self) = @_;

  return "table_".$self->id()."_ajax_target";
}

sub format_new_column_data {
  my ($self, $col, $data) = @_;
  
  my $new_data = join('@^', @$data);
  
  # escape nasty quotes
  $new_data =~ s/'/\@1/g;
  $new_data =~ s/"/\@2/g;

  # get the name of the column
  my $name = $self->id() . "_col_" . $col->{num};

  # check for filter
  my $filter = "";  
  if ($col->{filter}) {
    my $operator = 'like';
    if (defined($col->{operator})) {
      $operator = $col->{operator};
    }
    my $operand = $col->{operand} || "";
    $filter = "<br><input type=hidden name='" . $col->{name} . "_operator' value='" . $operator . "' id='table_" . $self->id() . "_operator_" . ($col->{num} - 1) . "'><input type='text' name='" . $col->{name} . "' class='filter_item' value='" . $operand . "' size=5 id='table_" . $self->id() . "_operand_" . ($col->{num} - 1) . "' onkeypress='return check_submit_filter(event, \"" . $self->id() . "\");' style='width: 100%;' title='Enter Search Text'>";
  }
   
  # check if colum header click should sort
  if ($col->{sortable}) {
    $col->{name} = "<a href='javascript: table_sort(\"" . $self->id() . "\", \"" . $col->{num} . "\");' class='table_first_row' title='Click to sort'>" . $col->{name} . "&nbsp;<img src=\"./Html/up-arrow.gif\"><img src=\"./Html/down-arrow.gif\"></a>";
  }
    
  # make colname referencable by js
  my $new_column = "<span id='colname_$name'>".$col->{name}.$filter."</span>";

  # escape nasty quotes
  $new_column =~ s/'/\@1/g;
  $new_column =~ s/"/\@2/g;

  $new_column = qq~<input type='hidden' id='table_~.$self->id().qq~_new_column_data' value='~.$new_column."**".$new_data.qq~'><img src=\"$Conf::cgi_url/Html/clear.gif\" onload="var a=document.getElementById('table_~.$self->id().qq~_new_column_data').value.split('**');table_append_data('~.$self->id().qq~', a[0], a[1]);">~;
  
  return $new_column;
}

sub format_data {
  my ($self) = @_;

  my $hover_component;
  my $data = $self;
  my $id = 0;
  my $numcols = 0;
  if (ref($self) eq "WebComponent::Table") {
    $data = $self->data();
    $numcols = scalar(@{$self->columns});
    $hover_component = $self->application->component('TableHoverComponent'.$self->id());
    $id = $self->id();
  } else {
    $numcols = scalar(@{$data->[0]});
  }

  # iterate through the data
  my $good_data;
  my $onclicks_array   = [];
  my $highlights_array = [];
  my $y = 0;
  foreach my $row (@$data) {
    my $good_row = [];
    my $onclicks_row = [];
    my $highlights_row = [];
    my $z = 0;
    foreach my $cell (@$row) {
      if (ref($cell) eq "HASH") {
        my $cell_id = "cell_".$id."_".$z."_".$y;
	if (!defined($cell->{data})) {
	  $cell->{data} = " ";
	}
	if ($cell->{data} eq '') {
	  $cell->{data} = " ";
	}
        push(@$good_row, $cell->{data});
        if (exists($cell->{onclick})) { push(@$onclicks_row, $cell->{onclick}); } else { push(@$onclicks_row, ""); }
        if (exists($cell->{highlight})) { push(@$highlights_row, $cell->{highlight}); } else { push(@$highlights_row, ""); }
        if (exists($cell->{tooltip})) { $hover_component->add_tooltip($cell_id, $cell->{tooltip}); }
        if (exists($cell->{menu})) { $hover_component->add_menu($cell_id, $cell->{menu}->{titles}, $cell->{menu}->{links}); }
      } else {
        $cell = ' ' unless (defined $cell);
	if ($cell eq '') {
	  $cell = " ";
	}
        push(@$good_row, $cell);
        push(@$onclicks_row, "");
        push(@$highlights_row, "");
      }
      $z++;
    }
    while ($z<$numcols) {
      push(@$good_row, "");
      push(@$onclicks_row, "");
      push(@$highlights_row, "");
      $z++;
    }
    push(@$good_data, $good_row);
    push(@$onclicks_array, $onclicks_row);
    push(@$highlights_array, $highlights_row);
    $y++;
  }
  if (ref($self) eq "WebComponent::Table") {
    $self->data($good_data);
  }

  # check for highlights and onclick events
  my $highlights = "";
  my $onclicks = "";
  {
    my $rows = [];
    foreach my $row (@$highlights_array) {
      push(@$rows, join('@^', @$row));
    }
    $highlights = join('@~', @$rows);

    $rows = [];
    foreach my $row (@$onclicks_array) {
      push(@$rows, join('@^', @$row));
    }
    $onclicks = join('@~', @$rows);
  }

  # put the data into a string
  my $rows = [];
  foreach my $row (@{$good_data}) {
    my $quoted_row;
    foreach my $cell (@$row) {
      if (defined($cell)) {
	$cell =~ s/\^/\&\#94\;/g;
	$cell =~ s/\~/\&\#126\;/g;
	push(@$quoted_row, $cell);
      } else {
	push(@$quoted_row, '');
      }
    }
    push(@$rows, join('@^', @$quoted_row));
  }
  my $data_source = join('@~', @$rows);

  # escape nasty quotes
  $data_source =~ s/'/\@1/g;
  $data_source =~ s/"/\@2/g;
  $onclicks =~ s/'/\@1/g;
  $onclicks =~ s/"/\@2/g;

  return ($data_source, $onclicks, $highlights);
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/Table.js", "$Conf::cgi_url/Html/PopupTooltip.js"];
}

sub require_css {
  return "$Conf::cgi_url/Html/Table.css";
}

sub export_excel {
  my ($self) = @_;

  # see if the excel module is available
  eval { require Spreadsheet::WriteExcel; };
  if ($@) {
    $self->application->add_message('warning', "Excel export is not supported on this system.");
    return;
  }

  # the module is present, create the Excel object
  # open the workbook
  open my $fh, '>', \my $str or die "Failed to open filehandle: $!";
  my $workbook  = Spreadsheet::WriteExcel->new($fh);
  my $worksheet = $workbook->add_worksheet();

  # remember the current row number
  my $rownum = 0;

  # check if we have supercolumns
  if ($self->supercolumns) {
    my $scs = $self->supercolumns();
    my $colnum = 0;
    foreach my $sc (@$scs) {
      my $format = $workbook->add_format();
      $format->set_bold();
      $format->set_align('center');
      $format->set_border();
      $worksheet->merge_range($rownum, $colnum, $rownum, $colnum + $sc->[1] - 1, $sc->[0], $format);
      $colnum += $sc->[1];
    }
    $rownum++;
  }

  # get the column data
  my $cols = $self->columns();
  for (my $i=0;$i<scalar(@$cols);$i++) {
    my $colname = $cols->[$i];
    if (ref($colname)) {
      # check for tooltip
      if ($colname->{tooltip}) {
	$worksheet->write_comment($rownum, $i, $colname->{tooltip});
      }

      # get the column data
      $colname = $colname->{name};
      
    }
    my $format = $workbook->add_format();
    $format->set_bold();
    $format->set_align('center');
    $format->set_border();

    $worksheet->write($rownum, $i, $colname, $format);
  }
  $rownum++;

  # remember the previously picked colors
  my $colors = {};

  my $general_format = $workbook->add_format();

  # get the table data
  my $data = $self->data();
  foreach my $row (@$data) {
    for (my $i=0; $i<scalar(@$row); $i++) {
      my $format;
      my $content = $row->[$i];
      if (ref($content)) {
	# check for tooltip
	if ($content->{tooltip}) {
	  $content->{tooltip} =~ s/<br>/\n/g;
	  $worksheet->write_comment($rownum, $i, $content->{tooltip});
	}

	# check for highlighting
	if ($content->{highlight}) {
	  my ($r, $g, $b) = $content->{highlight} =~ /rgb\((\d+),\s*(\d+),\s*(\d+)\)/;
	  unless (exists($colors->{$r."-".$g."-".$b})) {
	    $colors->{$r."-".$g."-".$b} = scalar(keys(%$colors)) + 9;
	    $workbook->set_custom_color($colors->{$r."-".$g."-".$b}, $r, $g, $b);
	  }
	  $format = $workbook->add_format();
	  $format->set_bg_color($colors->{$r."-".$g."-".$b});
	}

	# get the cell content
	$content = $content->{data};	
      }
      my ($url, $name) = $content =~ /^<a href=['"]{1}(.+)['"]{1}[^>]*>(.+)<\/a>$/;
      if ($url && $name) {
	$worksheet->write_url($rownum, $i, $url, $name, $format ? $format : $general_format);
      } else {
	$worksheet->write($rownum, $i, $content, $format ? $format : $general_format);
      }
    }
    $rownum++;
  }

  # close the workbook
  $workbook->close();

  print "Content-Type:application/x-download\n";  
  print "Content-Length: " . length($str) . "\n";
  print "Content-Disposition:attachment;filename=table.xls\n\n";

  # The Excel file is now in $str. Remember to binmode() the output
  # filehandle before printing it.
  binmode STDOUT;
  print $str;
  
  exit;
}

sub show_column_select {
  my ($self, $show) = @_;

  if (defined($show)) {
    $self->{show_column_select} = $show;
  }

  return $self->{show_column_select};
}

sub preferences_key {
  my ($self, $key) = @_;

  if (defined($key)) {
    $self->{preferences_key} = $key;
  }

  return $self->{preferences_key};
}

sub set_visible_column_preferences {
  my ($self) = @_;

  my $application = $self->application;
  my $cgi = $application->cgi;
  
  my $setting = $cgi->param('pref_setting');
  my $pref_key = $cgi->param('pref_key');

  my $user = $application->session->user;
  
  my $prefs = $application->dbmaster->Preferences->get_objects( { user => $user,
								  name => 'table_pref_'.$pref_key });
  if (scalar(@$prefs)) {
    $prefs->[0]->value($setting);
  } else {
    $application->dbmaster->Preferences->create( { user  => $user,
						   name  => 'table_pref_'.$pref_key,
						   value => $setting } );
  }

  return "<span style='color: black;'>&nbsp;settings saved.</span><br>";
}

sub dynamic_data {
  my ($self, $dynamic_data) = @_;

  if (defined($dynamic_data)) {
    $self->{dynamic_data} = $dynamic_data;
  }

  return $self->{dynamic_data};
}

sub other_buttons {
  my ($self, $other_buttons) = @_;

  if (defined($other_buttons)) {
    $self->{other_buttons} = $other_buttons;
  }

  return $self->{other_buttons};
}

sub sequential_init {
  my ($self, $init) = @_;

  if (defined($init)) {
    $self->{sequential_init} = $init;
  }

  return $self->{sequential_init};
}

sub column_select_toggle {
  my ($self, $toggle) = @_;

  if (defined($toggle)) {
    $self->{column_select_toggle} = $toggle;
  }

  return $self->{column_select_toggle};
}
