package WebComponent::FeatureToolSelect;

# FeatureToolSelect - component to select a tool to be run on a feature

use strict;
use warnings;

use Conf;
use URI::Escape;

use base qw( WebComponent );

1;


=pod

=head1 NAME

FeatureToolSelect - component to select a tool to be run for a feature

=head1 DESCRIPTION

WebComponent to return a form with a select box which lists all available tools. The list is taken from global/LinksToTools.

=head1 METHODS

=over 4


=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {

  my $self = shift->SUPER::new(@_);
  
  return $self;
}

=item * B<output> ()

Returns the html output of the FeatureToolSelect component.

=cut

sub output {
  my ($self) = @_;

  my $cgi = $self->application->cgi;
  my $id = $cgi->param('feature') || "";

  my $tool_select_box = "";
  if (open(TMP,"<$Conf::global/LinksToTools")) {
    $tool_select_box = "<select name='tool'>";
    
    $/ = "\n//\n";
    while (defined($_ = <TMP>)) {
      # allow comment lines in the file
      next if (/^#/);
      my($tool,$desc, undef, $internal_or_not) = split(/\n/,$_);
      my $esc_tool = uri_escape($tool);
      unless (defined($internal_or_not)) {
	$internal_or_not = "";
      }
      next if ($tool eq 'Transmembrane Predictions');
      next if ($tool eq 'General Tools');
      next if ($tool eq 'For Specific Organisms');
      next if ($tool eq 'Other useful tools');
      next if ($tool =~ /^Protein Signals/);
      next if (($tool ne 'ProDom') && ($internal_or_not eq "INTERNAL"));
      $tool_select_box .= "<option value=\"$tool\">$tool</option>";
      $self->application->menu->add_entry('&raquo;Feature Tools', $tool, "?page=RunTool&tool=$esc_tool&feature=$id", "_blank");
    }
    close(TMP);
    $/ = "\n";

    $tool_select_box .= "</select>";
    
  } else {
    $self->application->add_message('warning', 'No tools found');
  }

  return $tool_select_box;
}
