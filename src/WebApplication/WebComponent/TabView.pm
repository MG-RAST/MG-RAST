package WebComponent::TabView;

# TabView - component for a tabular view

# $Id: TabView.pm,v 1.22 2011-01-22 17:54:36 redwards Exp $

use strict;
use warnings;
use Data::Dumper;
use base qw( WebComponent );

1;

=pod

=head1 NAME

TabView - component for a tabular view

=head1 DESCRIPTION

WebComponent for a tabular view

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

    my $self = shift->SUPER::new(@_);

    $self->{tabs} = [];
    $self->{subtabs} = {};
    $self->{sub_default} = {};
    $self->{width} = 300;
    $self->{height} = 200;
    $self->{default} = 0;
    $self->{orientation} = "horizontal";
    $self->{dynamic} = 0;

    return $self;
}

=item * B<output> ()

Returns the html output of the TabView component.

=cut

sub output {
    my ($self) = @_;

    # open surrounding table
    my $width = "width: " . $self->width() . "px;";
    my $height = "height: " . $self->height() . "px;";
	
    my ($tabview, $hidden)=("", "");
    if ($self->dynamic()) {
	# only supported for horizontal tabs
	if ($self->orientation() eq 'horizontal') {
	    $tabview .= "<input type='hidden' id='tab_view_dynamic_" . $self->id . "' value='yes' />";
	    if (@{$self->{tabs}} == 0) {
		$hidden = 'display: none;';
	    }
	} else {
	    if (@{$self->{tabs}} == 0) {
		die "Using tabular view without tabs.";
	    }
	}
    } else {
	if (@{$self->{tabs}} == 0) {
	    die "Using tabular view without tabs.";
	}
    }
    
    $tabview .= "<input type='hidden' id='" . $self->{_id} . "' value='" . $self->id() . "' />";
    $tabview .= "<table style='$height $width $hidden border-spacing: 0px;border-collapse: expression(\"separate\", cellSpacing = \"0px\");' id='tab_view_table_" . $self->id . "'>";

    # create tabview titles
    my $first = 1;
    my $i = 0;
    my $class;

    # check total number of tabs
    my $total = 0;
    foreach my $tab (@{$self->{tabs}}) {
        $total ++;
        if (exists($self->{subtabs}->{$i})) {
            $total += scalar(@{$self->{subtabs}->{$i}});
        }
        $i++;
    }
    $i = 0;

    # check for horizontal or vertical tabview
    if ($self->orientation eq "horizontal") {
        $tabview .= "<tr>";
        foreach my $tab (@{$self->{tabs}}) {
            if ($i == $self->default()) {
                $class = "tab_view_title_selected";
            } else {
                $class = "tab_view_title";
            }
            my $onclick = " onclick='tab_view_select(\"" . $self->id . "\", \"" . $i . "\");'";
            if ($tab->{disabled}) {
                $onclick = "";
            }
            $tabview .= "<td class='$class' name='" . $self->id . "_tabs' id='" . $self->id . "_tab_" . $i . "'$onclick>" . $tab->{name} . "</td>";
            $i++;
        }
        $tabview .= "<td class='tab_view_title_filler'>&nbsp;</td></tr>";

        # create content cell
        $tabview .= "<tr><td colspan='" . ($total + 1) . "' class='tab_view_content_td'>";
        $first = 1;
        $i = 0;
        foreach my $tab (@{$self->{tabs}}) {
            if ($i == $self->default()) {
                $class = "tab_view_content_selected";
            } else {
                $class = "tab_view_content";
            }
            my $div_id = $self->id . "_content_" . $i; 
            $tabview .= "<div style='height: 100%; width: 100%;' class='$class' name='" . $self->id . "_contents' id='" . $div_id . "'>" . $tab->{content} . "</div>"; 
            # Format a hidden form for JS to call execute_ajax on
            if( $tab->{'ajax'} ){
                $tabview .= "<input type=\"hidden\" id=\"".$self->id."_tabajax_".$i."\"  value=\"0;".$tab->{ajax}->[0].";".$div_id.";".$tab->{ajax}->[1];
				if(@{$tab->{'ajax'}} == 3) { $tabview .= ";".$tab->{ajax}->[2]."\" >"; }
				else { $tabview .= "\" >"; }
            }
            $i++;
        }
        $tabview .= "</td></tr>";
    } else {
        $i = 0;
        foreach my $tab (@{$self->{tabs}}) {
            $tabview .= "<tr>";
            if ($i == $self->default()) {
                $class = "tab_view_title_vertical_selected";
            } else {
                $class = "tab_view_title_vertical";
            }
            my $onclick = " onclick='tab_view_select(\"" . $self->id . "\", \"" . $i . "\", \"vert\");'";
            if ($tab->{disabled}) {
                $onclick = "";
            }
            $tabview .= "<td class='$class' name='" . $self->id . "_tabs' id='" . $self->id . "_tab_" . $i . "'$onclick>" . $tab->{name} . "</td>";
	    
	    if ($first) {
	      $first = 0;
	      $tabview .= "<td width=100% rowspan='" . ($total + 1) . "' class='tab_view_content_vertical_td'>";
	      my $h = 0;
	      foreach my $tab2 (@{$self->{tabs}}) {
		my $class2 = "tab_view_content";
		if ($h == $self->default()) {
		  $class2 = "tab_view_content_vertical_selected";
		}

		# check for subtabs
		if (exists($self->{subtabs}->{$h})) {
		  my $f = 0;
		  foreach my $subtab2 (@{$self->{subtabs}->{$h}}) {
		    my $class2 = "tab_view_content";
		    if ($h == $self->default && $f == $self->sub_default($h)) {
		      $class2 = "tab_view_content_vertical_selected";
		    }
		    $tabview .= "<div style='height: 100%; width: 100%;' class='$class2' name='" . $self->id . "_contents' id='" . $self->id . "_content_" . $h . "_" . $f . "'>" . $subtab2->{content} . "</div>";
		    $f++;
		  }
		}
		else{
		  
		  $tabview .= "<div style='height: 100%; width: 100%;' class='$class2' name='" . $self->id . "_contents' id='" . $self->id . "_content_" . $h . "'>" . $tab2->{content} . "</div>";
		}
		$h++;
	      }
	      $tabview .= "</td>";
	    }
	    $tabview .= "</tr>";
	    
	    # Add sub tab labels
	    if (exists($self->{subtabs}->{$i})) {
	      my $g = 0;
	      foreach my $subtab (@{$self->{subtabs}->{$i}}) {
		my $onclick = " onclick='tab_view_select(\"" . $self->id . "\", \"" . $i . "\", \"sub\", \"" . $g . "\");'";
		if ($subtab->{disabled}) {
		  $onclick = '';
		}
		$tabview .= "<tr><td class='$class' id='" . $self->id . "_subtab_" . $i . "_" . $g . "'$onclick>" . $subtab->{name} . "</td>";
		$g++;
	      }
	    }

	    $i++;
	  }
	
	$tabview .= "<tr><td class='tab_view_title_vertical_filler'>&nbsp;</td></tr>";
      }

    # close table
    $tabview .= "</table>";


    # on load select the default tab
    my $ori = ", \"1\"";
    if ($self->orientation eq "horizontal") {
      $ori = "";
    }
    my $onload = " onload='initialize_tab_view(\"" . $self->id . "\");";
	if ($hidden eq '') {
		$onload .= " tab_view_select(\"" . $self->id . "\", \"" . $self->default() . "\"$ori);'";
	} else {
		$onload .= "'";
	}

    $tabview .= "\n<img src='$Conf::cgi_url/Html/clear.gif' $onload>\n";

    return $tabview;
}

=item * B<add_tab> (I<tab_name>, I<tab_content>, I<disabled>)

Adds a tab to the tab view

=cut

sub add_tab {
  my $self 		= shift;
  my $tab_name		= shift;
  my $tab_content	= shift;
  my $ajax;
  my $disabled;
  foreach my $i (@_) {
	if(ref($i) eq 'ARRAY') {
		$ajax = $i;
	} else { $disabled = $i }
  }
	
  unless (defined($tab_name) && defined($tab_content)) {
    die "tab_name or tab_content not set in add_tab (name:$tab_name\ncontent:$tab_content)";
  }

  push(@{$self->{tabs}}, { name => $tab_name, content => $tab_content, ajax => $ajax || 0, disabled => $disabled || 0 });

  return 1;
}

=item * B<add_sub_tab> (I<supertab>, I<tab_name>, I<tab_content>, I<disabled>)

Adds a sub-tab to the tab view

=cut

sub add_sub_tab {
  my ($self, $supertab, $tab_name, $tab_content, $disabled) = @_;

  unless (defined($supertab) && defined($tab_name) && defined($tab_content)) {
    die "supertab, tab_name or tab_content not set in add_sub_tab";
  }

  unless (exists($self->{subtabs}->{$supertab})) {
    $self->{subtabs}->{$supertab} = [];
  }
 
  push(@{$self->{subtabs}->{$supertab}}, { name => $tab_name, content => $tab_content, disabled => $disabled || 0 });

 
  return 1;
}

=item * B<width> (I<width>)

Getter / Setter for the width attribute.
This determines the width of the component in pixels.

=cut

sub width {
  my ($self, $width) = @_;

  if (defined($width)) {
    $self->{width} = $width;
  }

  return $self->{width};
}

=item * B<height> (I<height>)

Getter / Setter for the height attribute.
This determines the height of the component in pixels. The height
of the tab headers will still be added to this value.

=cut

sub height {
  my ($self, $height) = @_;

  if (defined($height)) {
    $self->{height} = $height;
  }

  return $self->{height};
}

=item * B<default> (I<default>)

Getter / Setter for the default attribute.
This determines the which tab is initially in front.

=cut

sub default {
  my ($self, $default) = @_;

  if (defined($default)) {
    $self->{default} = $default;
  }

  return $self->{default};
}

sub sub_default {
  my ($self, $super, $sub) = @_;

  unless (defined($super)) {
    $super = 0;
  }

  if (defined($sub)) {
    $self->{sub_default}->{$super} = $sub;
  }
  
  my $sub_default = 0;
  if (exists($self->{sub_default}->{$super})) {
    $sub_default = $self->{sub_default}->{$super};
  }

  return $sub_default;
}

=item * B<orientation> (I<orientation>)

Getter / Setter for the orientation attribute.
This determines the orientation of the tab view. This can be either
'horizontal' or 'vertical'. Default is 'horizontal'.

=cut

sub orientation {
  my ($self, $orientation) = @_;

  if (defined($orientation)) {
    $self->{orientation} = $orientation;
  }

  return $self->{orientation};
}

sub dynamic {
    my ($self, $dynamic) = @_;

    if (defined($dynamic)) {
	$self->{dynamic} = $dynamic;
    }

    return $self->{dynamic};
}

sub require_css {
  return "$Conf::cgi_url/Html/TabView.css";
}

sub require_javascript {
  return ["$Conf::cgi_url/Html/TabView.js"];
}
