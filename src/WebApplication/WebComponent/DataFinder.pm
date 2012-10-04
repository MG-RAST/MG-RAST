package WebComponent::DataFinder;

use strict;
use warnings;

use base qw( WebComponent );

use Conf;

1;

sub new {
  my $self = shift->SUPER::new(@_);

  $self->{data} = {};
  $self->{max_elements} = 10;
  $self->{tag_order} = [];
  $self->{tag_expansion} = {};
  $self->{width} = 672;
  $self->{height} = 125;
  $self->{taget_function} = '';
  $self->{visible} = 1;

  return $self;
}

sub output {
  my ($self) = @_;

  my $content = "";
  my $ids = [];
  foreach my $id (sort(keys(%{$self->{data}}))) {
    my $tags = [];
    foreach my $tag (sort(keys(%{$self->{data}->{$id}}))) {
      push(@$tags, $tag."||".join("||", @{$self->{data}->{$id}->{$tag}}));
    }
    push(@$ids, $id.";;".join(";;", @$tags));
  }
  my $dstring = join("##", @$ids);

  my $tag_expansion = [];
  foreach my $t (@{$self->tag_order}) {
    if (defined($self->{tag_expansion}->{$t})) {
      push(@$tag_expansion, $self->{tag_expansion}->{$t});
    } else {
      push(@$tag_expansion, "0");
    }
  }

  my $visible = " display: none;";
  if ($self->visible) {
    $visible = "";
  }
  $content .= "<input type='hidden' id='data_finder_target_function' value='" . $self->target_function ."'>";
  $content .= "<input type='hidden' id='data_finder_tag_expansion' value='" . join("||", @$tag_expansion). "'>";
  $content .= "<input type='hidden' id='data_finder_tag_order' value='".join("||", @{$self->tag_order})."'>";
  $content .= "<input type='hidden' id='data_finder_data' value='$dstring'>";
  $content .= "<input type='hidden' id='data_finder_visible' value='".$self->visible."'>";
  $content .= "<input type='hidden' id='data_finder_max_elements' value='".$self->max_elements."'>";
  $content .= "<div id='data_finder_main' class='data_finder_main' style='margin-top: 15px; height: ".$self->height."; width: ".$self->width."px;$visible'></div>";
  my $crumbs = "";
  $content .= qq~<img src='$Conf::cgi_url/Html/clear.gif' onload='initialize_data_finder();'>~;
  
  return $content;
}

sub require_css {
  return "$Conf::cgi_url/Html/DataFinder.css";
}

sub require_javascript {
  return [ "$Conf::cgi_url/Html/DataFinder.js" ];
}

sub data {
  my ($self, $data) = @_;

  if (defined($data)) {
    $self->{data} = $data;
  }

  return $self->{data};
}

sub max_elements {
  my ($self, $max) = @_;

  if (defined($max)) {
    $self->{max_elements} = $max;
  }

  return $self->{max_elements};
}

sub tag_order {
  my ($self, $tags) = @_;

  if (defined($tags)) {
    $self->{tag_order} = $tags;
  }

  return $self->{tag_order};
}

sub tag_expansion {
  my ($self, $expansion) = @_;

  if (defined($expansion)) {
    $self->{tag_expansion} = $expansion;
  }

  return $self->{tag_expansion};
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

sub target_function {
  my ($self, $function) = @_;

  if (defined($function)) {
    $self->{target_function} = $function;
  }

  return $self->{target_function};
}

sub visible {
  my ($self, $visible) = @_;

  if (defined($visible)) {
    $self->{visible} = $visible;
  }

  return $self->{visible};
}
