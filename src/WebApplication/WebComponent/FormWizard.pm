package WebComponent::FormWizard;

# FormWizard - component for to create wizards for complex input forms

use strict;
use warnings;

use Data::Dumper;
use XML::Simple;
use WebComponent::FormWizard::DataStructures;
use Conf;

use base qw( WebComponent );

1;


=pod

=head1 NAME

FormWizard - component to create wizards for complex input forms

=head1 DESCRIPTION

WebComponent to create input forms in wizard form

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);

  $self->application->register_component('TabView', 'fw_tv_'.$self->id);
  $self->application->register_component('Hover', 'fw_hover_'.$self->id);
  $self->application->register_component('Hover' , 'fw_hover_migs_'.$self->id);
  $self->application->register_component('Ajax', 'fw_ajax_'.$self->id);

  $self->{config_file} = undef;
  $self->{summary} = 0;
  $self->{orientation} = 'horizontal';
  $self->{width} = undef;
  $self->{height} = undef;
  $self->{noprefix} = 0;
  $self->{prefix} = '';
  $self->{using_categories} = 0;
  $self->{page} = $self->application->page;
  $self->{struct} = WebComponent::FormWizard::DataStructures->new();
  $self->{allow_random_navigation} = 0;
  $self->{submit_button} = 1;
  $self->{enable_ajax} = 0;

  $self->{debug} = $self->application->cgi->param('debug') || "0" ;


  return $self;
}

=item * B<output> ()

Returns the html output of the FormWizard component.

=cut

sub output {
  my ($self) = @_;

  # get some variables
  my $application = $self->application;
  my $cgi = $application->cgi;

  # get data
  $self->{data} = $self->{struct}->data();

  # create the tabview
  my $tv = $application->component('fw_tv_'.$self->id);
  $tv->orientation($self->orientation);
  if ($self->width) {
    $tv->width($self->width);
  }
  if ($self->height) {
    $tv->height($self->height);
  }
  my $ori = "";
  if ($self->orientation eq 'vertical') {
    $ori = ', "vertical"';
    if ($self->using_categories) {
      $ori = ', "sub"';
    }
  }
  
  # get the current step
  my $current_step = $cgi->param('wz_'.$self->id().'_current_step') || 1;
  my $content = "";

  if ($self->enable_ajax) {
    $content .= $self->application->component('fw_ajax_'.$self->id)->output;
  }
  $content .= $self->application->page->start_form('wizard_form_'.$self->id()) if ($self->submit_button);
  
  # javascript: all 'selectall_' multi-selects have all options submitted
  my $formName = $self->form_name();
  my $scripts .= qq~
<script>
function enable_multi_select() {
  fwForm = document.getElementById('$formName'); 
  for (i = 0; i < fwForm.elements.length; ++i) {
    if (fwForm.elements[i].type == 'select-multiple') {
      if ( /selectall_/.test(fwForm.elements[i].name) ) {
        fwForm.elements[i].disabled = false;
        for (j = 0; j < fwForm.elements[i].options.length; ++j) {
          fwForm.elements[i].options[j].selected = true;
        }
        fwForm.elements[i].name = fwForm.elements[i].name.replace(/selectall_/,'');
      }
    }
  }
  return true;
}
</script>
~;
  $content .= $scripts;

  my $h   = -1 ; # Tab counter , TabView starts with 0 
  my $i   = 1;
  my $cat = $self->categories();
  
  # remember number of categories and add submit button to all steps in the last category if steps are exclusive
  my $nr_categories    = scalar @{ $cat->{order} };
  my $category_counter = 0 ;

  foreach my $cat_name (@{ $cat->{order} }) {
    $category_counter++;
    $h++;

    # need subcategories
    my $multiple_steps  = 0;
    my $nr_steps_in_cat = scalar @{$cat->{groups}->{$cat_name}};
    if ( $nr_steps_in_cat > 1 ) {
      if ( $cat->{groups}->{$cat_name}->[0]->{exclusive} ) {
	my $step_content = $self->create_group_selection_box( $cat->{groups}->{$cat_name} , $cat_name , $category_counter || $h ) || "";
	my ($last, $next) = $self->create_navigation_buttons( $tv , $h , $nr_categories , $i , $cat->{ nr_steps } , 1 , 1 , 1 , $ori);	
	my $navigation_buttons = "<table width=100%><tr><td style='text-align: left;'>$last</td><td style='text-align: right;'>$next</td></tr></table>";
	
	$tv->add_tab($cat_name,  $navigation_buttons . "<hr>" . $step_content . $navigation_buttons);

	$i++;
	next;
      } else {
	$tv->add_tab($cat_name , '');
	$multiple_steps = 1;
      }
    }
  
    # steps per category
    my $nr_step_per_category = 1;

    foreach my $step (@{$cat->{groups}->{$cat_name}}) {
      my $step_content = "<table style='height: 100%; width: 100%;'><tr><td>";
      
      if ($step->{intro} || $step->{data}->{intro}) {
	$step_content .= "<p>". ($step->{intro} || $step->{data}->{intro})."</p>";
      }      
      $step_content .= $self->layout_questions($step, $h, $i);
      if ($step->{summary}) {
	$step_content .= "<p>".$step->{summary}."</p>";
      }
   
      my ($last, $next) = $self->create_navigation_buttons( $tv , $h , $nr_categories , $i , $cat->{ nr_steps } , 1 , 1 , 1 , $ori);

      $step_content .= "</td></tr><tr><td style='vertical-align: bottom;'><table width=100%><tr><td style='text-align: left;'>$last</td><td style='text-align: right;'>$next</td></tr></table></td></tr></table>";
      
      if (scalar @{$cat->{groups}->{$cat_name}} > 1) {
	my $checked = "";
	my $disabled = 0;
	my $title = $step->{title} || $step->{data}->{title};
	if ($step->{exclusive}) {
	  if ($nr_step_per_category == 1) {
	    $checked = " checked=checked"
	  } else {
	    $disabled = 1;
	  }
	  $title = "<span title='this step is exclusive, you can only select one'><input type='radio' name='$cat_name'$checked onclick='enable_subtab(this, ".$tv->id.", $h, ".($nr_step_per_category-1).");'>".$title."</span>";
	}
	if ($self->{allow_random_navigation}) {
	  $disabled = 0;
	}
	$tv->add_sub_tab( $h, $title, $step_content, $disabled );
      } else {
	my $disabled = 1;
	if ($self->{allow_random_navigation}) {
	  $disabled = 0;
	}
	$tv->add_tab( ($step->{title} || $step->{data}->{title}) , $step_content, $disabled );
      }
      $i++;
      $nr_step_per_category++;
    }
  }

  $content .= $tv->output();
  $content .= $self->application->page->end_form() if ($self->submit_button);
  my $hover = $self->application->component('fw_hover_'.$self->id);
  $content .= $hover->output();

  return $content;
}

sub config_file {
  my ($self, $fh) = @_;

  if (defined($fh)) {
    $self->{config_file} = $fh;
    $self->{struct}->readFormWizardConfig($fh);
    $self->{struct}->config2data();
  }
  return $self->{config_file};
}

sub summary {
  my ($self, $summary) = @_;

  if (defined($summary)) {
    $self->{summary} = $summary;
  }
  return $self->{summary};
}

sub orientation {
  my ($self, $orientation) = @_;

  if (defined($orientation)) {
    $self->{orientation} = $orientation;
  }
  return $self->{orientation};
}

sub width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{width} = $width;
  }
  return $self->{width};
}

sub height {
  my ($self, $height) = @_;

  if (defined($height)) {
    $self->{height} = $height;
  }
  return $self->{height};
}

sub layout_questions {
  my ($self, $step, $category_nr, $step_nr) = @_;

  my ($layout, $questions , $info_width ) = ( ($step->{layout} || $step->{data}->{layout}) , 
					      $step->{question} ,  
					      ($step->{info_width} || $step->{data}->{info_width} || '')
					    );

  my $content = "";
  my $mandatory_hiddens = "";
  my $hover = $self->application->component('fw_hover_'.$self->id);
  $hover->add_tooltip('mandatory', "This question is mandatory");
  $hover->add_tooltip('migs', "This is a MIGS term");

  $self->application->add_message('info' , "Found " . scalar @$questions . " questions!") if ($self->debug) ;

  # check which layout to use
  if ($layout eq "single-column") {
    $content .= "<table>";
    my $i = 1;
    foreach my $question (@$questions) {
      my $help = "";
      if (defined($question->{help})) {
	my $qid = "wizard_" . $self->id . "_q_" . $category_nr . "_" . $step_nr . "_" . $i;
	$hover->add_tooltip($qid, $question->{help});
	$help .= "&nbsp;&nbsp;<img src='$Conf::cgi_url/Html/wac_infobulb.png' onmouseover='hover(event, \"" . $qid . "\", \"" . $hover->id() . "\");'>";
      }
      if (defined($question->{info})) {
	my $info = $question->{info};
	$help .= "&nbsp;&nbsp;<i>". $info."</i>";

      }
      if (length($help)) {
	my $hstring = $help;
	if ($info_width) {
	  $help = "<td style='width: " . $info_width . "px;'>";
	} else {
	  $help = "<td nowrap='nowrap'>";
	}
	$help .= $hstring . "</td>";
      }
      my $mandatory = '';
      if ($question->{mandatory}) {
	$mandatory_hiddens .= "<input type='hidden' name='mandatory_hiddens_".$step_nr."_".$self->id."' value='".$question->{name}."|".$question->{text}."'>";
	$mandatory = "<span style='font-weight: bold; color: red; cursor: pointer;' onmouseover='hover(event, \"mandatory\", \"" . $hover->id() . "\");'><sup>*</sup></span>";
      }
      if ($question->{migs}) {
	$content .= "<tr><td>";
	$content .=  "<div style='font-weight: bold; color: blue;' onmouseover='hover(event, \"migs\", \"" . $hover->id() . "\");'>";
	$content .= $question->{text}."$mandatory</div><br>".$self->question_type($question, $i)."</td>$help</tr>";
      }
      else{
	$content .= "<tr><td>".$question->{text}."$mandatory<br>".$self->question_type($question, $i)."</td>$help</tr>";
      }
      $i++;
    }
    $content .= "</table>";
  } 
  else {
    $content .= "<table width='90%'>";
    my $i = 1;
    
    foreach my $question (@$questions) {    
      my $help = "";
      if (defined($question->{help})) {	
	my $qid = "wizard_" . $self->id . "_q_" . $category_nr . "_" . $step_nr . "_" . $i;
	$hover->add_tooltip($qid, $question->{help});
	$help .= "&nbsp;&nbsp;<img src='$Conf::cgi_url/Html/wac_infobulb.png' onmouseover='hover(event, \"" . $qid . "\", \"" . $hover->id() . "\");'>";
      }
      if (defined($question->{info})) {	
	my $info = $question->{info};
	$info =~ s/([^\n]{ 50 , 70})(?:\b\s*|\n)/$1<br>/gi;
	$help .= "&nbsp;&nbsp;<i>".$question->{info}."</i>";
      }
      if (length($help)) {
	my $hstring = $help;
	if ($info_width) {
	  $help = "<td style='width: " . $info_width . "px;'>";
	} else {
	  $help = "<td nowrap='nowrap'>";
	}
	$help .= $hstring . "</td>";
      }
      
      my $mandatory = '';
      if ($question->{mandatory}) {
	$mandatory_hiddens .= "<input type='hidden' name='mandatory_hiddens_".$step_nr."_".$self->id."' value='".$question->{name}."|".$question->{text}."'>";
	$mandatory = "<span style='font-weight: bold; color: red; cursor: pointer;' onmouseover='hover(event, \"mandatory\", \"" . $hover->id() . "\");'><sup>*</sup></span>";
      }
      if ($question->{migs}) {
	$content .= "<tr><td>";
	$content .=  "<span style='font-weight: bold; color: blue;' onmouseover='hover(event, \"migs\", \"" . $hover->id() . "\");'>";
	$content .= $question->{text}."$mandatory</span></td><td>".$self->question_type($question, $i)."</td><td>$help</td></tr>";
      } else {
	$content .= "<tr><td>".$question->{text}."$mandatory</td><td>".$self->question_type($question, $i)."</td><td>$help</td></tr>";
      }
      $i++;
    }
    $content .= "</table>";
  }
  $content .= $mandatory_hiddens;

  return $content;
}

sub prefill {
  my ($self, $prefill) = @_;
  
  if (defined($prefill)) {
    $self->{prefill} = $prefill;
  }
  return $self->{prefill};
}

sub question_type {
  my ($self, $question, $step_num) = @_;
  my $prefill = $self->prefill();
  my $content = "";

  $question->{default} = '' unless ($question->{default});
 
  if (exists($question->{id})) {
    $content .= "<span id='" . $question->{id} . "'>";
  }

  my $name = $question->{name} || '';
  unless ($name) {
    my $value =  $question->{text};
    $value =~s/\s+/_/g;
    $name = lc $value;
    $question->{name} = $name;
  }

  # set question default to prefill value if defined
  if ( (ref $prefill) && (defined $prefill->{$name}) ) {
    $question->{default} = $prefill->{$name};
  }
  # else empty array, give it a string
  elsif ( (ref($question->{default}) eq 'ARRAY') && (@{$question->{default}} == 0) ) {
    $question->{default} = [''];
  }
  
  # set default to scalar if list (for types in formwizard)
  my $default_scalar = '';
  if ( ref($question->{default}) ) {
    if ( (ref($question->{default}) eq 'ARRAY') && scalar(@{$question->{default}}) ) {
      $default_scalar = $question->{default}->[0];
    }
  } else {
    $default_scalar = $question->{default};
  }

  # write div for ajax
  $content .= "<div id='ajax_main_$name'>";

  if ($question->{type} eq "select") {
    $content .= "<select name='$name'>\n<option value=''>Please Select</option>\n";
    foreach my $option (@{$question->{options}}) {
      unless (ref($option) eq "HASH") {
	$option->{value} = $option;
	$option->{text} = $option->{value};
      }
      unless (defined $option->{value}) {
	my $value = $option->{text};
	$value =~s/\s+/_/g;
	$option->{value} = lc $value;
      }
      my $default = ($default_scalar eq $option->{value}) ? " selected='selected'" : "";
      $content .= "<option value='".$option->{value}."'$default>".$option->{text}."</option>\n";
    }
    $content .= "</select>";
  } elsif ($question->{type} eq "radio") {
    foreach my $option (@{$question->{options}}) {
      unless (ref($option) eq "HASH") {
	my $opt = {};
	$opt->{value} = $option;
	$opt->{text} = $option;
	$option = $opt;
      }
      my $default = ($default_scalar eq $option->{value}) ? " checked='checked'" : "";
      $content .= "<input type='radio' name='$name' value='".$option->{value}."'$default>".$option->{text};
    }
  } elsif ($question->{type} eq "checkbox") {
    foreach my $option (@{$question->{options}}) {
      unless (ref($option) eq "HASH") {
	my $opt = {value => $option, text => $option, checked => 0 };
	$option = $opt;
      }
      my $default = "";
      if($default_scalar eq $option->{value}) {
	$option->{checked} = 1;
      }
      if ($option->{checked}) {
	$default = " checked='checked'";
      }
      $content .= "<input type='checkbox' name='$name' value='".$option->{value}."'$default>".$option->{text}."<br>";
    }
  } elsif ($question->{type} eq "list") {
    $content .= "<select name='$name' multiple='multiple'>";
    foreach my $option (@{$question->{options}}) {
      unless (ref($option) eq "HASH") {
	my $opt = {value => $option, text => $option, checked => 0 };
	$option = $opt;
      }
      my $default = "";
      if($default_scalar eq $option->{value}) {
	$option->{selected} = 1;
      }
      if ($option->{selected}) {
	$default = " selected='selected'";
      }
      $content .= "<option value='".$option->{value}."'$default>".$option->{text}."</option>";
    }
    $content .= "</select>";
  } elsif ($question->{type} eq "textarea") {
    $content .= "<textarea name='$name' value='$default_scalar' cols='30' rows='10'>$default_scalar</textarea>";
  } elsif ($question->{type} eq "text") {
    $content .= $self->text_field($question, $default_scalar);
  } elsif ($question->{type} eq 'date') {
    $question->{size}       = "size='10'";
    $question->{unit}       = '';
    $question->{validation} = "id='DPC_$name'";
    $content .= $self->text_field($question, $default_scalar);
  } elsif ($question->{type} eq "OOD_List") {
    $content .= $self->OOD_List($question);
  } elsif ($question->{type} eq "OOD_Tree") {
    $content .= $self->OOD_Tree($question);
  } elsif ($question->{type} eq "OOD_Ontology_Tree") {
    $content .= $self->OOD_Tree($question, 1);
  } elsif ($question->{type} eq 'user_list') {
    my $options = "";
    if ($question->{default} && (ref $question->{default} eq 'ARRAY')) {
      foreach my $p ( @{$question->{default}} ) {
	$options .= "<option value='$p' selected='selected'>$p</option>";
      }      
    }
    $content .= qq~
<table><tr>
  <td>
    <input type='text' id='text_$name' /><br>
    <input type='button' value='add' onclick='
      if (document.getElementById("text_$name").value.length) {
        document.getElementById("select_$name").add(new Option(document.getElementById("text_$name").value, document.getElementById("text_$name").value, 1, 1), null)
      }' />
    <input type='button' value='remove' onclick='
      if (document.getElementById("select_$name").options.length) {
        document.getElementById("select_$name").remove(document.getElementById("select_$name").options.length-1);
      }' />
  </td><td>
    <select name='$name' multiple=multiple size=5 disabled=disabled id='select_$name'>
      $options
    </select>
  </td>
</tr></table>
~;
  } elsif ($question->{type} eq 'user_kv_list') {
    my $options = "";
    if ($question->{default} && (ref $question->{default} eq 'ARRAY')) {
      foreach my $p ( @{$question->{default}} ) {
	$options .= "<option value='$p' selected='selected'>$p</option>";
      }      
    }
    $content .= qq~
<table><tr>
  <td>
    <input type='text' id='text_k_$name' />
    <input type='text' id='text_v_$name' /><br>
    <input type='button' value='add' onclick='
      if (document.getElementById("text_$name").value.length) {
        document.getElementById("select_$name").add(new Option(document.getElementById("text_k_$name").value+": "+document.getElementById("text_v_$name").value, document.getElementById("text_k_$name").value+": "+document.getElementById("text_v_$name").value, 1, 1), null)
      }' />
    <input type='button' value='remove' onclick='
      if (document.getElementById("select_$name").options.length) {
        document.getElementById("select_$name").remove(document.getElementById("select_$name").options.length-1);
      }' />
  </td><td>
    <select name='$name' multiple=multiple size=5 disabled=disabled id='select_$name'>"
      $options
    </select>
  </td>
</tr></table>
~;
  } else {
    my $error   = '';
    my $package = "WebComponent::FormWizard::" . $question->{type};
    {
      no strict;
      eval "require $package;";
      $error = $@;
    }

    if ($error) {
      # no package, default is text
      $content .= $self->text_field($question, $default_scalar, $error);
    }
    else {
      # create the object
      my $type = $package->new($self, $question);
      if (ref($type) && $type->isa($package) && $type->can("output")) {
	$content .= $type->output;
      } else {
	$content .= $self->text_field($question, $default_scalar, $error);
      }
    }
  }
  
  # close div for ajax
  $content .= "</div>";
  if (exists $question->{id}) { $content .= "</span>"; }
  
  return $content;
}

sub text_field {
  my ($self, $question, $default, $error) = @_;

## for debugging
#  $error = $error ? "<br><pre>$error</pre>" : "";
  $error = "";
  $question->{size}       = $question->{size} || '';
  $question->{validation} = $question->{validation} || '';
  my $default_package     = "WebComponent::FormWizard::Measurement";

  # if units included, use Measurement type
  if ($question->{unit} && (ref $question->{unit} eq "ARRAY")) {
    {
      no strict;
      eval "require $default_package;";
    }
    my $obj = $default_package->new($self, $question);
    if (ref($obj) && $obj->can("output")) { return $obj->output; }
  }

  return qq(<input type="text" name="$question->{name}" value="$default" $question->{size} $question->{validation} />$error);
}

sub form_name{
  my ($self, $name) = @_;

  if ($name) {
    $self->{form_name} = $name;
  }
  unless ($self->{form_name}) {
    $self->{form_name} = "forms.wizard_form_".$self->id();
  }
  return  $self->{form_name};
}

sub noprefix {
  my ($self, $noprefix) = @_;

  $self->{noprefix} = $self->{struct}->noprefix($noprefix);
  return $self->{noprefix};
}

sub prefix {
  my ($self, $prefix) = @_;

  $self->{prefix} = $self->{struct}->prefix($prefix);
  return $self->{prefix};
}

sub using_categories {
  my ($self, $categories) = @_;

  $self->{using_categories} = $self->{struct}->using_categories($categories);
  return $self->{using_categories};
}

sub categories {
  my ($self) = @_;
  return $self->{struct}->categories();
}

sub page {
  my ($self) = @_;
  return $self->{page};
}

sub data {
  my ($self) = @_;
  return $self->{struct}->data();
}

sub struct {
  my ($self) = @_;
  return $self->{struct};
}

sub enable_ajax {
  my ($self, $enable) = @_;

  if (defined($enable)) {
    $self->{enable_ajax} = $enable;
  }
  return $self->{enable_ajax};
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/datepickercontrol.js","$Conf::cgi_url/Html/FormWizard.js"];
}

sub require_css {
  return "$Conf::cgi_url/Html/datepickercontrol.css";
}

sub allow_random_navigation {
  my ($self, $allow) = @_;

  if (defined($allow)) {
    $self->{allow_random_navigation} = $allow;
  }
  return $self->{allow_random_navigation};
}

sub submit_button {
  my ($self, $allow) = @_;
  
  if (defined($allow)) {
    $self->{submit_button} = $allow;
  }
  return $self->{submit_button};
}

#
# Ontology Lookup
#

sub Ontology {
    my ($self, $question) = @_;

    # get page functions
    my $name = $question->{name} || '';
    my $cgi  = $self->application->cgi;
    my $wid  = $self->{_id};

    # Set params to remember and submit to ajax functions
    my $default_name  = (ref($question->{default}) && (ref($question->{default}) eq 'ARRAY')) ? $question->{default}->[0] : $question->{default};
    my $main_ajax_id  = $name ? "ajax_main_$name" : $cgi->param('main_ajax');	 
    my $edit_ajax_id  = $name ? "ajax_edit_$name" : $cgi->param('edit_ajax');
    my $question_name = $name || $cgi->param('question_name_ajax');
    my $question_type = $question->{type} || $cgi->param('question_type_ajax');
    my $question_text = $question->{text} || $cgi->param('question_text_ajax');
    
    unless ($question_type) {
      return "<p>missing question type</p>";
    }

    my $ajax_call = qq~
<a style='cursor: pointer;' onclick="
  if (document.getElementById('$name').value) {
    execute_ajax('Ontology_lookup','$edit_ajax_id','main_ajax=$main_ajax_id&edit_ajax=$edit_ajax_id&question_name_ajax=$question_name&question_type_ajax=$question_type&question_text_ajax=$question_text&selection='+document.getElementById('$name').value, null, null, null, 'FormWizard|$wid');
  } else {
    alert('you must enter a term to search');
  }">
  <b>search term</b></a>
~;

    my $content = qq~
<input name='$question_name' value='$default_name' id='$question_name' />&nbsp;
<input type='hidden' name='${question_name}_accession' value='' id='${question_name}_accession' />
<input type='hidden' name='${question_name}_definition' value='' id='${question_name}_definition' />
<input type='hidden' name='${question_name}_ontology' value='' id='${question_name}_ontology' />
$ajax_call<br>
<div id='$edit_ajax_id' style='cursor: pointer;'><div>
~;

    return $content;
}

sub Ontology_lookup {
  my ($self) = @_;
  
  my $cgi = $self->application->cgi;
  my $wid = $self->{_id};

  my $main_ajax_id     = $cgi->param('main_ajax');
  my $edit_ajax_id     = $cgi->param('edit_ajax');
  my $question_name    = $cgi->param('question_name_ajax');
  my $question_type    = $cgi->param('question_type_ajax');
  my $question_text    = $cgi->param('question_text_ajax');
  my $selection        = $cgi->param('selection');
  my $target_name_term = $cgi->param('target_name_term');
  my $target_name_desc = $cgi->param('target_name_desc');
  my $from_tree        = $cgi->param('from_tree');

  $selection =~ s/^\s+//;
  my @indexed_selection = split(/\s+/, $selection); 

  use LWP::Simple;
  use XML::Simple;

  my $response = get "http://terminizer.org/terminizerBackEnd/service?sourceText=$selection";
  unless ($response) { return "No look up service available"; }

  my $ref = XMLin($response, forcearray => ["MatchedTermList","MatchedTerm","Token"]);
  my $term_table = "<p><table><tr><td><b>Ontology term</b></td><td><b>Definition</b></td></tr>";

    my $num_found = 0;
  foreach my $matched_token ( @{$ref->{MatchedTermList}} ) {
    my $hits = $matched_token->{MatchedTerm};
       
    foreach my $hit (@$hits) {
      my $definition  = $hit->{Definition} unless (ref $hit->{Definition});
      my $accession   = $hit->{Accession};
      my ($suggested) = $hit->{OmixedItemID} =~/Term\/terminizer\/(.+)/;
      my %token_id    = map { $_ => 1 } split ("," , $hit->{TokenIndices});
      
      my $matched = '';
      for (my $i=0 ; $i < scalar @indexed_selection ; $i++) {
	if ($token_id{$i}) { $matched .= "<b> $indexed_selection[$i] </b> "; }
	else               { $matched .= $indexed_selection[$i] . " "; }
      }
      next unless $definition;
      $num_found++;
      
      my $suggested_safe = $suggested;
      $suggested_safe =~ s/"/\\"/g;
      $suggested_safe =~ s/'/\\'/g;
      
      my $definition_safe = $definition;
      $definition_safe =~ s/"/\\"/g;
      $definition_safe =~ s/'/\\'/g;
      
      my $event = "";
      if ($from_tree) {
	$event = qq~
<a onclick='
  document.getElementById("add_entry_button").style.display="inline";
  document.getElementById("$target_name_term").value="$suggested_safe";
  document.getElementById("$target_name_desc").value="$definition_safe";
  document.getElementById("$edit_ajax_id").innerHTML="";'> $suggested </a>
~;
      } else {
	$event = qq~
<a onclick='
  document.getElementById("$question_name").value="$suggested";
  document.getElementById("$edit_ajax_id").innerHTML="";'> $suggested </a
~;
      }
      $term_table .= "<tr><td>$event</td><td><def>" . ($definition || 'no definition available') . "</def></td></tr>\n";
    }
  }

  unless ($num_found) {
    my $event = "";
    if ($from_tree) {
      $event = qq~
<a onclick='
  document.getElementById("add_entry_button").style.display="inline";
  document.getElementById("$edit_ajax_id").innerHTML="";'> - no definitions found - </a>
~;
    } else {
      $event = " - no definitions found - ";
    }
    $term_table .= "<tr><td colspan=2>$event</td></tr>";
  }
  $term_table .= "</table></p>\n";

  my $content = $term_table;

  unless ($from_tree) {
    $content .= qq~
<a style='cursor: pointer;' onclick="
  if (document.getElementById('$question_name').value) {
    execute_ajax('Ontology_lookup', '$edit_ajax_id',
                 'main_ajax=$main_ajax_id&edit_ajax=$edit_ajax_id&question_name_ajax=$question_name&question_type_ajax=$question_type&question_text_ajax=$question_text&selection='+document.getElementById('$question_name').value,
                 null, null, null, 'FormWizard|$wid');
  } else {
    alert('you must enter a term to search');
  }"'>
  <b>search term</b></a>
~;
  }

  return $content;
}

#
# Ontology on Demand List structure
#

sub OOD_List {
  my ($self, $question) = @_;
 
  # get page functions
  my $name  = $question->{name} || '';
  my $wid   = $self->{_id};
  my $app   = $self->application;
  my $cgi   = $app->cgi;
  my $ood   = $app->data_handle('OOD');
  
  # Set params to remember and submit to ajax functions
  my $main_ajax_id  = $name ? "ajax_main_$name" : $cgi->param('main_ajax');	 
  my $edit_ajax_id  = $name ? "ajax_edit_$name" : $cgi->param('edit_ajax');
  my $question_name = $name || $cgi->param('question_name_ajax');
  my $question_type = $question->{type} || $cgi->param('question_type_ajax');
  my $question_text = $question->{text} || $cgi->param('question_text_ajax') || '';
  my $question_def  = (ref($question->{default}) && (ref($question->{default}) eq 'ARRAY')) ? $question->{default}->[0] : $question->{default};
  my $cat = $cgi->param('cat') || $question->{ontologyName} || $question->{ood_category} || $name;
  my $new_ood_entry = $cgi->param('new_ood_entry') || '';

  unless ($question_type) {
    return "<p>missing question type</p>";
  }
  unless ($ood) {
    $app->add_message('warning', "No OOD, please contact the administrator");
    return "<p>OOD not found</p>";
  }
  unless ($cat) {
    $app->add_message('warning', "No category for OOD, please contact the administrator");
    return "<p>Category $cat not found</p>";
  }

  # connect to DB and retrive data for list
  my $cats = $ood->Category->get_objects( {name => $cat} );
  my $category;
  if ( scalar(@$cats) ) {
    $category = $cats->[0];
  } else {
    $category = $ood->Category->create( {name        => $cat,
					 ID          => "FormWizard_$cat",
					 extendable  => "1",
					 description => "created automaticallly from xml template " .
					                ($self->{config_file} ? $self->{config_file} : '')
					 } );
  }
  
  unless(ref $category) {
    $app->add_message('warning', "category $question_name not found");
    return "<p>category not found</p>";
  }

  # add new term to DB
  if ($cgi->param('new_ood_entry')) {
    $self->OOD_add2list( $category, $app, $cgi, $ood );
  }
  
  my $entries = $self->get_list($ood, $category);
  if ($question->{sort_order} && $question->{sort_order} eq "alphabetical") {
    @$entries = sort { $a->name cmp $b->name } @$entries;
  }
  my @labels = map { $_->name } @$entries;
  my @values = map { $_->_id } @$entries;
  unshift(@labels, "Please select");
  unshift(@values, "unknown");
  
  my $select = "no component selected";
  
  if ($question->{'display'} && ($question->{'display'} eq "FilterSelect")) {    
    $app->register_component('FilterSelect', "FilterSelect$name");
    my $filter_select_component = $app->component("FilterSelect$name");
    $filter_select_component->labels( \@labels );
    $filter_select_component->values( \@values );
    $filter_select_component->size(8);
    $filter_select_component->width(200);
    $filter_select_component->name($name);
    $select = $filter_select_component->output;
  }
  else{
    $select = $cgi->popup_menu( -id      => "parent_$name",
				-name    => $name,
				-values  => \@labels,
				-default => $question_def
			      );
  }
  
  # field for final value
  my $table = "<table><tr>\n<td><div>$select</div></td>";
  if ( $app->session->user ) {
    $table .= qq~
<td><div id="$edit_ajax_id" style="cursor: pointer;">
    <a style='cursor: pointer;' onclick="
      execute_ajax('OOD_edit_list', '$edit_ajax_id',
                   'main_ajax=$main_ajax_id&edit_ajax=$edit_ajax_id&question_name_ajax=$question_name&question_type_ajax=$question_type&question_text_ajax=$question_text&selection='+document.getElementById('parent_$name').options[document.getElementById('parent_$name').selectedIndex].value+'&cat=$cat',
                   null, null, null, 'FormWizard|$wid');">
    <b>add term</b></a>
  </div>~;
  }
  $table .= "</td></tr></table>\n";
  
  return $table;
}

sub OOD_edit_list {
  my ($self) = @_;

  my $cgi           = $self->application->cgi;
  my $main_ajax_id  = $cgi->param('main_ajax');
  my $edit_ajax_id  = $cgi->param('edit_ajax');
  my $question_name = $cgi->param('question_name_ajax');
  my $question_type = $cgi->param('question_type_ajax');
  my $selection     = $cgi->param('selection');
  my $cat           = $cgi->param('cat');
  if ($selection eq 'Please select') {
    $selection = '';
  }
  
  my $button_txt = ($selection eq 'unknown' || $selection eq '') ? 'add term' : "add term after '$selection'";
  my $fw_id      = $self->{_id};
  
  return qq~
<table><tr>
  <th>New term</th>
  <td><input id='new_ood_entry_term' name='new_ood_entry' type='text' size='30' maxlength='200'></td>
</tr><tr>
  <th>Definition</th>
  <td><textarea id='new_ood_entry_definition' name='new_ood_entry_definition' value='' cols='30' rows='10'></textarea></td>
</tr><tr>
  <td colspan=2>
    <input type="button" value="$button_txt" onclick="
      execute_ajax('$question_type', '$main_ajax_id',
                   'main_ajax=$main_ajax_id&edit_ajax=$edit_ajax_id&question_name_ajax=$question_name&question_type_ajax=$question_type&new_ood_parent=$selection&new_ood_entry='+document.getElementById('new_ood_entry_term').value+'&new_ood_entry_definition='+document.getElementById('new_ood_entry_definition').value+'&cat=$cat',
                   null, null, null, 'FormWizard|$fw_id');" />
    <input type="button" value="cancel" onclick="
      execute_ajax('$question_type', '$main_ajax_id',
                   'main_ajax=$main_ajax_id&edit_ajax=$edit_ajax_id&question_name_ajax=$question_name&question_type_ajax=$question_type&new_ood_entry='+document.getElementById('new_ood_entry_term').value+'&cat=$cat',
                   null, null, null, 'FormWizard|$fw_id');" />
  </td>
</tr></table>~;
}

sub OOD_add2list{
  my ($self, $category, $app, $cgi, $ood) = @_; 
  
  my $parent     = $cgi->param('new_ood_parent')           || "";
  my $new_term   = $cgi->param('new_ood_entry')            || "";
  my $definition = $cgi->param('new_ood_entry_definition') || "";
  
  unless ($new_term && $definition) {
    $app->add_message('warning', "No definition or term, aborting.");
    return 0;
  }
  
  # check if the name already exists
  my $entry = $ood->Entry->get_objects( { name     => $new_term,
					  category => $category } );
  if (scalar(@$entry)) {
    $app->add_message('warning', "term $new_term already exists in the ontology");
    return 0;
  }

  my $root = $ood->Entry->get_objects( { category => $category,
					 parent   => undef } );
  $root = scalar(@$root) ? $root->[0] : undef;

  # term does not exists, create it
  my $new_node = $ood->Entry->create( { ID         => $category->ID,
					name       => $new_term,
					category   => $category,
					definition => $definition,
					creator    => $app->session->user,
					user_entry => '1',
					editable   => '0',
				      } );

  unless (ref $new_node) {
    $app->add_message('warning',"Can't add $new_term to " . $category->name . ", aborting");
    return 0;
  }

  if ($parent) {
    my $parent_object = $ood->Entry->get_objects( { name     => $parent,
						    category => $category } );
    if (scalar(@$parent_object)) {
      $parent_object = $parent_object->[0];
      my $child;
      if (scalar(@{$parent_object->child})) {
	$child = shift @{$parent_object->child};
      }
      push(@{$parent_object->child}, $new_node);
      $new_node->parent($parent_object);
      if ($child) {
	push(@{$new_node->child}, $child);
	$child->parent($new_node);
      }
    } else {
      $app->add_message('warning',"could not retrieve parent entry from ontology, aborting");
      $new_node->delete();
      return 0;
    }
  } elsif ($root) {
    push(@{$new_node->child}, $root);
    $root->parent($new_node);
  }

  $app->add_message('info',"Entry " . $new_node->name . " for " . $new_node->category->name . " created");

  return 1;
}

sub get_list {
  my ($self, $ood, $category) = @_;
 
  my $entries = $ood->Entry->get_objects( {category => $category} );
  my $parents = {};
  my $sorted_entries = [];

  foreach my $entry (@$entries) {
    if ($entry->parent) {
      $parents->{$entry->parent->_id} = $entry;
    } else {
      if (defined($sorted_entries->[0])) {
	@$entries = sort { $a->{name} cmp $b->{name} } @$entries;
	return $entries;
      } else {
	$sorted_entries->[0] = $entry;
      }
    }
  }
  
  for (my $i=0; $i<scalar(@$entries) - 1; $i++) {
    next unless (defined($parents->{$sorted_entries->[scalar(@$sorted_entries) - 1]}));
    push(@$sorted_entries, $parents->{$sorted_entries->[scalar(@$sorted_entries) - 1]->_id});
  }

  return $sorted_entries;
}

#
# Ontology on Demand Tree structure
#

sub OOD_Tree {
  my ($self, $question, $use_ontology) = @_;

  my $wid  = $self->{_id};
  my $name = $question->{name};
  my $app  = $self->application;
  my $cgi  = $app->cgi;
  my $ood  = $app->data_handle('OOD');

  # Set params to remember and submit to ajax functions
  my $main_ajax_id  = $name ? "ajax_main_$name" : $cgi->param('main_ajax') ;	 
  my $edit_ajax_id  = $name ? "ajax_edit_$name" : $cgi->param('edit_ajax') ;
  my $question_name = $name || $cgi->param('question_name_ajax');
  my $question_type = "OOD_Tree";
  my $question_text = $question->{text} || $cgi->param('question_text_ajax') || '';
  my $question_def  = (ref($question->{default}) && (ref($question->{default}) eq 'ARRAY')) ? $question->{default}->[0] : $question->{default};
  my $cat = $cgi->param('cat') || $question->{ontologyName} || $question->{name};
  my $new_ood_entry = $cgi->param('new_ood_entry') || '';
  
  unless ($question_type) {
    return "<p>missing question type</p>";
  }
  unless ($ood) {
    $app->add_message('warning', "No OOD, please contact the administrator");
    return "<p>OOD not found</p>";
  }
  unless ($cat) {
     $app->add_message('warning', "Category for OOD, please contact the administrator");
    return "<p>Category not found</p>";
  }

  # connect to DB and retrive data for list
  my $cats = $ood->Category->get_objects( {name => $cat} );
  my $category;
  if (scalar(@$cats)) {
    $category = $cats->[0];
  } else {
    $category = $ood->Category->create( {name        => $cat,
					 ID          => "FormWizard_$cat",
					 extendable  => "1",
					 description => "created automaticallly from xml template " .
					                ($self->{config_file} ? $self->{config_file} : '')
					} );
  }

  unless (ref $category) {
    $app->add_message('warning', "category $question_name not found");
    return "<p>category not found</p>";
  }

  my $tree_component_name = "tree_".$question_name."_".$question->{type};
  $app->register_component('Tree',  $tree_component_name);
  my $tree = $app->component( $tree_component_name );

  # add new term to DB
  if ($cgi->param('new_ood_entry')) {
    $self->OOD_add2tree($category, $app, $cgi, $ood);
  }

  my $entries = $self->get_tree($ood, $category, $question_def);
  my $tid = $tree->id;
  $tree->data($entries);
  $tree->selectable(1);
  $tree->select_leaves_only(0);
  $tree->name("tree_".$question_name);

  # field for final value
  unless (ref($question->{default})) {
    $question->{default} = [ $question->{default} ];
  }

  my $table = qq~
<table><tr>
  <td><select name="selectall_$question_name" multiple="multiple" style="min-width:120px" size="10" id="q_sel_${cat}_$question_name">
~;

  foreach my $d (@{$question->{default}}) {
    if ($d) { $table .= "<option value='$d' selected=selected>$d</option>\n"; }
  }

  $table .= qq~
    </select></td>
  <td align="center" style="padding-left: 15px;">
    <input type="button" value=" <-- " id="b_add_${cat}_$question_name" /><br>
    <input type="button" value=" --> " id="b_del_${cat}_$question_name" /><br>
    <input type="button" value="Clear All" id="b_clear_${cat}_$question_name" />
  </td><td>
    <div style="padding-left: 15px;">~ . $tree->output . "</div></td>\n";

  if ( $app->session->user ) {
      $table .= qq~
  <td><div id="$edit_ajax_id" style="cursor: pointer;"><a onclick="
    if (document.getElementById('${tid}tree_$question_name')) {
      execute_ajax('OOD_edit_tree', '$edit_ajax_id', 'main_ajax=$main_ajax_id&edit_ajax=$edit_ajax_id&question_name_ajax=$question_name&question_type_ajax=$question_type&question_text_ajax=$question_text&selection='+document.getElementById('${tid}tree_$question_name').value+'&tid=${tid}&cat=$cat&use_ont=1', null, null, null, 'FormWizard|$wid');
    } else {
      alert('you must select a category first'); }">
  <b>add term</b></a></div>
~;
  }
  $table .= "</td></tr></table>\n";
  
  my $content = qq~
<script type="text/javascript">
\$(document).ready( function() {
  \$("#b_add_${cat}_$question_name").click( function() {
    var term = \$("#${tid}tree_$question_name").val();
    if ( term ) {
      \$("#q_sel_${cat}_$question_name").append('<option selected="selected" value="'+term+'">'+term+'</option>');
    }
    return false;
  });
  \$("#b_del_${cat}_$question_name").click( function() {
    \$("#q_sel_${cat}_$question_name option:selected").remove();
    return false;
  });
  \$("#b_clear_${cat}_$question_name").click( function() {
    \$("#q_sel_${cat}_$question_name option").remove();
    return false;
  });
});
</script>
$table
~;

  return $content;
}

sub OOD_add2tree {
  my ($self, $category, $app, $cgi, $ood) = @_; 
  
  my $parent     = $cgi->param('new_ood_parent')           || "";
  my $new_term   = $cgi->param('new_ood_entry')            || "";
  my $definition = $cgi->param('new_ood_entry_definition') || "";
  
  unless ($new_term && $definition) {
    $app->add_message('warning', "No definition or term, aborting.");
    return 0;
  }
  
  # check if the name already exists
  my $entry = $ood->Entry->get_objects( { name     => $new_term,
					  category => $category } );
  if (scalar(@$entry)) {
    $app->add_message('warning', "term $new_term already exists in the ontology");
    return 0;
  }

  my $root = $ood->Entry->get_objects( { category => $category,
					 parent   => undef } );
  if (scalar(@$root)) {
    $root = $root->[0];
  } else {
    $root = undef;
  }

  # term does not exists, create it
  my $new_node = $ood->Entry->create( { ID         => $category->ID,
					name       => $new_term,
					category   => $category,
					definition => $definition,
					creator    => $app->session->user,
					user_entry => '1',
					editable   => '0',
				      } );

  unless (ref $new_node) {
    $app->add_message('warning', "Can't add $new_term to " . $category->name . ", aborting");
    return 0;
  }
  
  if ($parent) {
    my $parent_object = $ood->Entry->get_objects( { name     => $parent,
						    category => $category } );
    if (scalar(@$parent_object)) {
      $parent_object = $parent_object->[0];
      push @{$parent_object->child}, $new_node;
      $new_node->parent($parent_object);
    } else {
      $app->add_message('warning', "could not retrieve parent entry from ontology, aborting");
      $new_node->delete();
      return 0;
    }
  }

  $app->add_message('info' , "Entry " . $new_node->name . " for " . $new_node->category->name . " created");

  return 1;
}

sub OOD_edit_tree {
  my ($self, $value) = @_;

  my $wid           = $self->{_id};
  my $cgi           = $self->application->cgi;
  my $main_ajax_id  = $cgi->param('main_ajax');
  my $edit_ajax_id  = $cgi->param('edit_ajax');
  my $question_name = $cgi->param('question_name_ajax');
  my $question_type = $cgi->param('question_type_ajax');
  my $selection     = $cgi->param('selection');
  my $tid           = $cgi->param('tid');
  my $cat           = $cgi->param('cat');
  my $use_ontology  = $cgi->param('use_ont');
  
  my $button = "";
  if ($selection eq 'unknown' || $selection eq '') {
    $button = qq~
<input type="button" value="add root node" onclick="
  execute_ajax('$question_type', '$main_ajax_id',
               'main_ajax=$main_ajax_id&edit_ajax=$edit_ajax_id&question_name_ajax=$question_name&question_type_ajax=$question_type&new_ood_entry='+document.getElementById('new_ood_entry_term').value+'&new_ood_entry_definition='+document.getElementById('new_ood_entry_definition').value+'&cat=$cat',
               null, null, null, 'FormWizard|$wid');">
~;
  } else {
    my $visible = $use_ontology ? " style='display: none;'" : "";
    $button .= qq~
&nbsp;&nbsp;&nbsp;<input id="add_entry_button" type="button" value="add term as subcategory below $selection" onclick="
  execute_ajax('$question_type', '$main_ajax_id'
               'main_ajax=$main_ajax_id&edit_ajax=$edit_ajax_id&question_name_ajax=$question_name&question_type_ajax=$question_type&new_ood_parent='+document.getElementById('${tid}tree_$question_name').value+'&new_ood_entry='+document.getElementById('new_ood_entry_term').value+'&new_ood_entry_definition='+document.getElementById('new_ood_entry_definition').value+'&cat=$cat',
               null, null, null, 'FormWizard|$wid');"$visible>
~;
  }
  
  my $ajax_call = "";
  if ($use_ontology) {
    $ajax_call = qq~
&nbsp;<a style='cursor: pointer;' onclick="
  if (document.getElementById('new_ood_entry_term').value) {
    execute_ajax('Ontology_lookup', 'new_ood_entry_ont_hits',
                 'edit_ajax=new_ood_entry_ont_hits&target_name_term=new_ood_entry_term&target_name_desc=new_ood_entry_definition&from_tree=1&selection='+document.getElementById('new_ood_entry_term').value,
                 null, null, null, 'FormWizard|$wid');
  } else {
    alert('you must enter a term to search'); }">
 <b>search term</b></a>
~;
  }

  my $html = qq~
<table>
  <tr>
    <th>New term</th>
    <td><input id='new_ood_entry_term' name='new_ood_entry' type='text' size='30' maxlength='200'>$ajax_call</td>
  </tr><tr>
    <th>Definition</th>
    <td><textarea id='new_ood_entry_definition' name='new_ood_entry_definition' value='' cols='30' rows='10'></textarea></td>
  </tr>~;

  if ($use_ontology) { $html .= "<tr><td colspan=2 id='new_ood_entry_ont_hits'></td></tr>\n"; }

  $html .= qq~<tr>
    <td colspan=2>$button&nbsp;&nbsp;&nbsp;<input type="button" value="cancel" onclick="
      execute_ajax('$question_type', '$main_ajax_id',
                   'main_ajax=$main_ajax_id&edit_ajax=$edit_ajax_id&question_name_ajax=$question_name&question_type_ajax=$question_type&new_ood_entry='+document.getElementById('new_ood_entry_term').value+'&cat=$cat',
                   null, null, null, 'FormWizard|$wid');"></td>
  </tr>
</table>
~;

  return $html;
}

sub get_tree {
  my ($self, $ood, $category, $default) = @_;

  unless ($default) { $default = ""; }
  my $tree    = []; 
  my $entries = $ood->Entry->get_objects( {category => $category} );
  my $parents = {};

  # print STDERR Dumper $category ; 
  # print STDERR Dumper $entries ; 

  foreach my $entry (@$entries) {
    if ($entry->user_entry) {
       $entry->{label} = "<b>" . $entry->{name} . "</b>";
    }
    else{
      $entry->{label} = $entry->{name};
    }
    $entry->{value}    = $entry->{name};
    $entry->{selected} = "selected" if ($entry->{value} eq $default) ;
  
    if ($entry->parent) {
      push(@{$parents->{$entry->parent->_id}}, $entry);
    } else {
      push(@$tree, $entry);
    }
  }
  @$tree = sort { $a->{name} cmp $b->{name} } @$tree;
  
  foreach my $e (@$tree) { tree_children($e, $parents); }

  return $tree;
}

sub tree_children {
  my ($entry, $parents) = @_;

  if (exists($parents->{$entry->_id})) {
    $entry->{children} = $parents->{$entry->_id};
    foreach my $e (@{$entry->{children}}) {
      tree_children($e, $parents);
    }
  } else {
    $entry->{children} = [];
  }

  return;
}

sub create_navigation_buttons{
  my ( $self , $tabview , $current_tab_nr , $max_tabs , $step_nr_global ,  $max_steps_global , $step_nr_local , $max_steps_local , $exclusive , $orientation) = @_ ;
  
  
  my $next = "<input type='button' value='next' onclick='if(check_mandatory(".$self->id.", $step_nr_global)){tab_view_select(\"".$tabview->id()."\", ". ($current_tab_nr+1) ."$orientation);}'>";
  my $last = "<input type='button' value='previous' onclick='tab_view_select(\"".$tabview->id()."\", ".($current_tab_nr - 1)."$orientation);'>";
  if (($max_steps_local > 1) && (! $exclusive)) {
    $next = "<input type='button' value='next' onclick='if(check_mandatory(".$self->id.", $step_nr_global)){tab_view_select(\"".$tabview->id()."\", $current_tab_nr , \"sub\" , $step_nr_local);}'>" if ($step_nr_local < $max_steps_local ) ;
    $last = "<input type='button' value='previous' onclick='tab_view_select(\"".$tabview->id()."\", $current_tab_nr , \"sub\" , ".($step_nr_local - 2).");'>"  if ($step_nr_local > 1) ;
  }
  if ($step_nr_global == 1) {
    $last = "";
  }
  if ( ( ($current_tab_nr + 1) == $max_tabs and $exclusive ) or $step_nr_global ==  $max_steps_global ) {
    if ($self->submit_button){
      $next = "<input type='button'  value='finish' onclick='enable_multi_select() ; ".$self->form_name().".submit();'>" ;
    }
    else{
      $next = ' ';
    }
  }
  
  return ($last , $next);
}

sub create_group_selection_box{
  my ($self , $steps ,  $catName , $cat_nr) = @_ ;
  
  my $application = $self->application;
  my $cgi = $application->cgi;

  my @values;
  my %labels;
  my $popup_name = "popup_".$catName ;
  $catName    =~ s/[\s\'\"]+/_/g ;
  $popup_name =~ s/[\s\'\"]+/_/g ;

  my $content = '';
  $content .= "<select id='$popup_name' name='$popup_name'  onchange=\"switch_category_display('$popup_name')\">\n" ;
  $content .= "<option value=''>Please select</option>\n" ;
  my $tab_divs = '' ;
 
  my $step_nr = 0 ;
  foreach my $step (@$steps){
    my $label = $step->{title} || $step->{data}->{title} || "-1" ;
    my $value = $label ;
    $value =~ s/[\s\"\'\/]+/_/g ;
    push @values , $value ;
    $labels{$value} = $label ;

    $content .= "<option value='$value'>$label</option>\n" ;

    my $step_content = $self->layout_questions( $step , $cat_nr, $step_nr) ; 
    
    $step_nr++;
    $tab_divs .= " <div id='div_sub_$value' style='display:none'>$step_content</div>\n";
  }
  
  $content .= "</select>\n<hr>\n";
  $content .= "<input type='hidden'  name='current_selection_$popup_name' id='current_selection_$popup_name' value='' >\n";
  $tab_divs .= "<div id='div_display_$catName' style='display:none'></div>\n" ;
  
  $content .= $tab_divs . "\n" ; 

  my $scripts = "<script>\n";
  $scripts .= qq~
function switch_display_$catName (DISPLAY , MENU) {  
  var menu      = document.getElementById(MENU);
  var selection = menu.options[menu.options.selectedIndex].value;
  var old_selection = document.getElementById( 'current_selection_' + MENU ).value ;

  alert( "New: " + selection + " Index: " + menu.options.selectedIndex );
  alert ("Old: " + old_selection);
  var new_div = document.getElementById( "div_sub_" + selection );
  var old_div = document.getElementById( "div_sub_" + old_selection );

  document.getElementById( 'current_selection_' + MENU ).value = selection ;
  new_div.style.display="inline";
  old_div.style.display="none";
}~; 

  $scripts .= "</script>\n";
  $content .= $scripts ;

  return $content ;
};

sub debug {
  my ($self) = @_ ;
  return $self->{debug} ;
}
