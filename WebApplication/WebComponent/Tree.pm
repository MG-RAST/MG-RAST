package WebComponent::Tree;

use strict;
use warnings;

use base qw( WebComponent );

1;

=pod

=head1 NAME

Tree - component for all kinds of trees

=head1 DESCRIPTION

WebComponent for all kinds of trees

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  $self->{data} = [];
  $self->{display_method} = 'explorer';
  $self->{selectable} = 0;
  $self->{select_leaves_only} = 1;
  $self->{select_multiple} = 0;
  $self->{name} = 'tree';

  return $self;
}

=item * B<output> ()

Returns the html output of the Table component.

=cut

sub output {
  my ($self) = @_;

  unless (scalar(@{$self->data})) {
    return "Tree component called without nodes";
  }

  # initialize variables
  my $tree = "";

  if ($self->display_method() eq 'explorer') {
    $tree = $self->generate_display_explorer();
  } else {
    return "Tree component called with invalid display method";
  }

  return $tree;
}

sub selectable {
  my ($self, $selectable) = @_;

  if (defined($selectable)) {
    $self->{selectable} = $selectable;
  }

  return $self->{selectable};
}

sub select_leaves_only {
  my ($self, $only) = @_;

  if (defined($only)) {
    $self->{select_leaves_only} = $only;
  }

  return $self->{select_leaves_only};
}

sub select_multiple {
  my ($self, $multiple) = @_;

  if (defined($multiple)) {
    $self->{select_multiple} = $multiple;
  }

  return $self->{select_multiple};
}

sub name {
  my ($self, $name) = @_;

  if (defined($name)) {
    $self->{name} = $name;
  }

  return $self->{name};
}

sub generate_display_explorer {
  my ($self) = @_;

  my $html = "\n<div id='tree_" . $self->id() . "'>";

  my $selecteds = "";

  my $data = $self->data();
  my $i = 0;
  foreach my $node (@$data) {
    $html .= "\n<div name='tree_level_0' id='tree_node_" . $self->id() . "_" . $i . "'>";

    if (scalar(@{$node->{children}})) {
      if ($node->{expanded}) {
	$html .= "<img id='tree_img_" . $self->id() . "_" . $i . "' src=\"$Global_Config::cgi_url/Html/minus.gif\" style='cursor: pointer;' onclick='expand(\"" . $self->id() . "\", \"" . $i . "\");'>&nbsp;";
      } else {
	$html .= "<img id='tree_img_" . $self->id() . "_" . $i . "' src=\"$Global_Config::cgi_url/Html/plus.gif\" style='cursor: pointer;' onclick='expand(\"" . $self->id() . "\", \"" . $i . "\");'>&nbsp;";
      }
    } else {
      $html .= "<img src=\"$Global_Config::cgi_url/Html/none.gif\">&nbsp;";
    }
    
    if ($self->selectable && (!(scalar(@{$node->{children}})) || !$self->select_leaves_only)) {
      my $val = $node->{label};
      if (defined($node->{value})) {
	$val = $node->{value};
      }
      my $color = '';
      if (defined($node->{selected}) && $node->{selected}) {
	$color = " color: #0000ff;";
	$selecteds .= "<input type='hidden' name='" . $self->name . "' value='" . $node->{value} . "'>";
      }
      $html .= "<span id='tree_span_" . $self->id() . "_" . $i . "' style='cursor: pointer;$color' onclick='tree_node_select(\"" . $self->id() . "\", \"" . $i . "\");'><input type='hidden' value='" . $val . "'>";
    }
    $html .= $node->{label};
    if ($self->selectable && (!(scalar(@{$node->{children}})) || !$self->select_leaves_only)) {
      $html .= "</span>";
    }
    
    if (scalar(@{$node->{children}})) {
      if ($node->{expanded}) {
	$html .="<div style='margin-left: 15px;' name='tree_level_" . ($node->{level} + 1) . "'  id='tree_div_" . $self->id() . "_" . $i . "'>";
      } else {
	unless ($node->{level}) {
	  $node->{level} = 0;
	}
	$html .="<div style='margin-left: 15px; display: none;' name='tree_level_" . ($node->{level} + 1) . "'  id='tree_div_" . $self->id() . "_" . $i . "'>";
      }
      foreach my $child (@{$node->{children}}) {
	$html .= "\n";
	$i++;
	($html, $i, $selecteds) = $self->display_explorer_child($html, $child, $i, $selecteds);
      }
      $html .= "</div>";
    }
    $html .="</div>";
    $i++;
  }

  $html .= "</div>\n";
  
  if ($self->selectable) {
    $html .= "<input type='hidden' id='tree_name_" . $self->id() . "' value='".$self->name()."'>";
    $html .= "<input type='hidden' id='tree_select_multiple_" . $self->id . "' value='" . $self->select_multiple . "'>";
    $html .= "<span id='tree_selected_" . $self->id . "'>".$selecteds."</span>";
  }

  return $html;
}

sub display_explorer_child {
  my ($self, $html, $node, $i, $selecteds) = @_;

  if (scalar(@{$node->{children}})) {
    if ($node->{expanded}) {
      $html .= "<img id='tree_img_" . $self->id() . "_" . $i . "' src=\"$Global_Config::cgi_url/Html/minus.gif\" style='cursor: pointer;' onclick='expand(\"" . $self->id() . "\", \"" . $i . "\");'>&nbsp;";
    } else {
      $html .= "<img id='tree_img_" . $self->id() . "_" . $i . "' src=\"$Global_Config::cgi_url/Html/plus.gif\" style='cursor: pointer;' onclick='expand(\"" . $self->id() . "\", \"" . $i . "\");'>&nbsp;";
    }
  } else {
    $html .= "<img src=\"$Global_Config::cgi_url/Html/none.gif\" style='cursor: pointer;'>&nbsp;";
  }

  if ($self->selectable && (!(scalar(@{$node->{children}})) || !$self->select_leaves_only)) {
    my $val = $node->{label};
    if (defined($node->{value})) {
      $val = $node->{value};
    }
    my $color = '';
    if (defined($node->{selected}) && $node->{selected}) {
      $color = " color: #0000ff;";
      $selecteds .= "<input type='hidden' name='" . $self->name . "' value='" . $node->{value} . "'>";
    }
    $html .= "<span id='tree_span_" . $self->id() . "_" . $i . "' style='cursor: pointer;$color' onclick='tree_node_select(\"" . $self->id() . "\", \"" . $i . "\");'><input type='hidden' value='" . $val . "'>";
  }
  $html .= $node->{label};
  if ($self->selectable && (!(scalar(@{$node->{children}})) || !$self->select_leaves_only)) {
    $html .= "</span>";
  }
  $html .= "<br>";
  if (scalar(@{$node->{children}})) {
    if ($node->{expanded}) {
      $html .="<div style='margin-left: 15px;' name='tree_level_" . ($node->{level} + 1) . "'  id='tree_div_" . $self->id() . "_" . $i . "'>";
    } else {
      unless ($node->{level}) {
	$node->{level} = 0;
      }
      $html .="<div style='margin-left: 15px; display: none;' name='tree_level_" . ($node->{level} + 1) . "'  id='tree_div_" . $self->id() . "_" . $i . "'>";
    }
    foreach my $child (@{$node->{children}}) {
      $i++;
      ($html, $i, $selecteds) = $self->display_explorer_child($html, $child, $i, $selecteds);
    }
    $html .= "</div>";
  }

  return ($html, $i, $selecteds);
}

sub add_node {
  my ($self, $params) = @_;

  my $node = Node->new($params);
  push(@{$self->{data}}, $node);

  return $node;
}

sub data {
  my ($self, $data) = @_;

  if (defined($data)) {
    $self->{data} = $data;
  }

  return $self->{data};
}

sub display_method {
  my ($self, $display_method) = @_;

  if (defined($display_method)) {
    $self->{display_method} = $display_method;
  }

  return $self->{display_method};
}

sub require_javascript {
  return ["$Global_Config::cgi_url/Html/Tree.js"];
}

package Node;

sub new {
    my ($class, $params) = @_;

    unless (defined($params)) {
      return undef;
    }

    my $self = { 'value' => $params->{'value'},
		 'selected' => $params->{'selected'},
		 'label' => $params->{'label'},
		 'attributes' => $params->{'attributes'},
		 'parent' => $params->{'parent'},
		 'expanded' => $params->{expanded} || 0,
		 'children' => []
	       };
    
    if (defined($self->{parent})) {
      $self->{level} = $self->{parent}->{level} + 1;
    } else {
      $self->{level} = 0;
    }

    bless $self, $class;

    return $self;
}

sub add_child {
  my ($self, $params) = @_;

  $params->{parent} = $self;
  my $child = new Node($params);
  push(@{$self->{children}}, $child);
  
  return $child;
}

sub label {
  my ($self, $label) = @_;

  if (defined($label)) {
    $self->{label} = $label;
  }

  return $self->{label};
}

sub expanded {
  my ($self, $expanded) = @_;

  if (defined($expanded)) {
    $self->{expanded} = $expanded;
  }

  return $self->{expanded};
}

1;
