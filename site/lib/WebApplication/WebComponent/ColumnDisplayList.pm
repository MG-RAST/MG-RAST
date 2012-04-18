#!/usr/bin/perl -w

#
# Copyright (c) 2003-2006 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#

package WebComponent::ColumnDisplayList;

    use strict;
    use Tracer;

use base qw(WebComponent);

=head1 

=head2 Introduction

The column display list component displays two scrolling list boxes and allows
the user to move fields between them. The boxes are intended to indicate columns
to be displayed and columns to be hidden, but they could theoretically be used
for anything when the user is presented with a list of labels and wants to
select what to keep and what to discard.

The box on the left will be the OUT box and the box on the right will be the IN
box.

Note that at the current time, the user can only shift one column at a time.
This may change in the future.

=head3 Linking to a Table Component

This component can be linked to a [[TablePm]] component so as to trigger
automatic showing and hiding of columns in the table. If this is done, the web
page must provide the name of a function that will be called using the
[[AjaxPm]] facility. The function will be called as an instance of the current
web page. The CGI parameters available to it will be as follows.

=over 4

=item rowKeyList

Tilde-delimited list of the IDs for all the table rows.

=item parmCache

The value of the L</parmCache> field.

=item colName

The name of the new column.

=item linkedComponent

The ID of the linked component.

=back

To plot the new column, the function should call the C<format_new_column_data>
method of the table, as shown in the example below.

    my $tableID = $mainTable->id();
    my $retVal = CGI::img({ src => "$FIG_Config::cgi_url/Html/clear.gif",
                        onload => "changeHiddenField('$tableID', '$colName')" }) .
                       $mainTable->format_new_column_data($colHdr, \@values);
    return $retVal;

In the example, C<$colHdr> is a [[TablePm]] column definition. This could be a
string (equal to the column label) or it could be a hash reference describing
the various filtering and display options.

If a table is linked, then the display list will reshuffle its columns. For this
reason, you must output the display list before the linked table. Otherwise, the
columns won't line up properly.

=head3 new

    my $cdsComponent = ColumnDisplayList->new();

Construct a new ColumnDisplayList component.

=cut

sub new {
    # Get the parameters.
    my ($class, @parms) = @_;
    # Construct the base class.
    my $retVal = $class->SUPER::new(@parms);
    # Set defaults for the various parameters.
    $retVal->{outCaption} = "Displayed columns:";
    $retVal->{inCaption} = "Hidden columns:";
    $retVal->{boxSize} = 6;
    # Return the object.
    return $retVal;
}

=head2 Virtual Methods

=head3 output

    $cdsComponent->output();

Return the html output of this component.

=cut

use constant POINTERS => { in => '<=',  out => '=>' };
use constant ANTITYPE => { in => 'out', out => 'in' };

sub output {
    my ($self) = @_;
    # Get the application object.
    my $application = $self->application();
    # Get access to the data store.
    my $fig = $application->data_handle('FIG');
    # Get our unique component ID.
    my $selfID = $self->id();
    # Get access to the form fields.
    my $cgi = $application->cgi();
    # Get this component's parameters.
    my $ajaxFunction = $self->ajaxFunction;
    my $metadata = $self->metadata;
    my $rowKeyList = $self->rowKeyList;
    my $linkedComponent = $self->linkedComponent;
    my $parmCache = $self->parmCache;
    my $inCaption = $self->inCaption;
    my $outCaption = $self->outCaption;
    my $boxSize = $self->boxSize;
    my $inFieldName = $self->inFieldName;
    # This hash will be used to save hidden fields, mapping field IDs to values.
    my %hidden;
    # The HTML data lines will go in here.
    my @dataLines = ();
    # Do some validation. The metadata is non-negotiable.
    Confess("Invalid or missing metadata for $selfID.")
        unless defined $metadata && ref $metadata eq 'HASH';
    # If we have an ajax function we need a row key list.
    if ($ajaxFunction) {
        Confess("Row key list missing or invalid for $selfID.")
            unless defined $rowKeyList && ref $rowKeyList eq 'ARRAY';
        # Save the row key list and the parm cache as hidden fields.
        $hidden{"rowKeyList$selfID"} = join("~", @$rowKeyList);
        $hidden{"parmCache$selfID"} = $parmCache || "";
    } else {
        # If there's no ajax function, we'll pass it around as an empty string.
        $ajaxFunction = "";
    }
    # Now we begin working with the list boxes. The first task is to map each
    # column name to its label.
    my %columnMap;
    for my $col (keys %$metadata) {
        my $colHdr = $metadata->{$col}->{header};
        $columnMap{$col} = (ref $colHdr eq 'HASH' ? $colHdr->{name} : $colHdr);
    }
    # This will map the names of the visible columns to their order numbers.
    my %visibleColumns;
    # Now we need to find which columns go where. There's the IN box, the OUT
    # box, and nowhere. We process the items in order by label so that the labels
    # are alphabetical when the lists are displayed.
    my %columnSets = ( in => [], out => [] );
    for my $colName (Tracer::SortByValue(\%columnMap)) {
        my $col = $metadata->{$colName};
        # We'll set this to the proper place to put the column.
        my $place;
        # Is this column visible?
        if ($col->{visible}) {
            # Yes. It belongs to the IN box unless it's permanent.
            $place = 'in';
            # Put it in the visible column list.
            $visibleColumns{$colName} = $metadata->{$colName}->{order};
        } else {
            # Not visible, so it goes in the OUT box.
            $place = 'out';
        }
        # This column only goes in a list box if it is NOT permanent.
        if (! $col->{permanent}) {
            push @{$columnSets{$place}}, $colName;
        }
    }
    # If there is a hidden field for the in-list, create it now. If there's not,
    # pass around an empty string for its name.
    if ($inFieldName) {
        $hidden{$inFieldName} = join("~", @{$columnSets{in}});
    } else {
        $inFieldName = "";
    }
    # We'll use this for the linked component ID.
    my $linkedComponentID = "";
    if (defined $linkedComponent) {
        # We have a linked component. Remember its ID.
        $linkedComponentID = $linkedComponent->id();
        # Compute the real column layout for it.
        my @orderedColumnNames = Tracer::SortByValue(\%visibleColumns);
        $linkedComponent->columns([ map { $metadata->{$_}->{header} } @orderedColumnNames ]);
        # Save the column layout as a field.
        $hidden{"layout$linkedComponentID"} = join("~", @orderedColumnNames);
    }
    # This entire component is a horizontally-centered table. The next step is
    # to start the table and put in captions for the two boxes. There are
    # actually three columns-- out box, buttons, in box-- but the buttons don't
    # have captions.
    push @dataLines, CGI::start_table({ class => 'DLS' });
    push @dataLines, CGI::Tr(CGI::th([$outCaption, "", $inCaption]));
    # We need to build the two list boxes and the two buttons. We do that
    # in these hashes. The keys are 'in' and 'out'.
    my (%boxes, %buttons);
    # This will be the prefix used in the box names.
    my $boxID = "cds_box_$selfID";
    # Do everything twice: once for OUT (left) and once for IN (right).
    for my $type (qw(out in)) {
        # Compute the name for the other type.
        my $antiType = ANTITYPE->{$type};
        # We only use the ajax function when moving to the IN list.
        my $ajaxParm = ($type eq 'in' ? $ajaxFunction : "");
        # Create our button event. The button moves to this type from the other.
        # So, if we're IN, the button moves from OUT and vice versa.
        my $onClick = $self->JavaCall(moveColumn => $type, "$boxID$antiType",
                                       "$boxID$type", $linkedComponentID,
                                       $ajaxFunction, $inFieldName, $selfID);
        # Format the button.
        $buttons{$type} = CGI::button(-class => 'button', -onClick => $onClick,
                                      -value => POINTERS->{$type});
        # Format the selection box.
        $boxes{$type} = CGI::scrolling_list(-id => "$boxID$type",
                                            -values => $columnSets{$type},
                                            -labels => \%columnMap,
                                            -size => $boxSize);
    }
    # Assemble the buttons into a table cell.
    my $buttonCell = "$buttons{out}<br /><br />$buttons{in}";
    # Now we create our second table row.
    push @dataLines, CGI::Tr(CGI::td([$boxes{in}, $buttonCell, $boxes{out}]));
    # Close the table.
    push @dataLines, CGI::end_table();
    # Now we create the final set of HTML lines.
    my @lines;
    # Insert the hidden fields.
    push @lines, map { CGI::hidden(-name => $_, -id => $_, -value => $hidden{$_}) }
                    keys %hidden;
    # Add the data lines.
    push @lines, @dataLines;
    # Return everything.
    return join("\n", @lines);
}

=head3 require_javascript

    my $list = $cdsComponent->require_javascript();

Return a list of URLs for the javascript that should be included if this
component is on a page.

=cut

sub require_javascript {
    return ["$FIG_Config::cgi_url/Html/ColumnDisplayList.js",
            "$FIG_Config::cgi_url/Html/Ajax.js"];
}

=head3 require_css

    my $style = $cdsComponent->require_css();

Return the URL for the style sheet that should be included if this component is
on a page.

=cut
sub require_css {
    return "$FIG_Config::cgi_url/Html/ColumnDisplayList.css";
}

=head2 Property Methods

=head3 ajaxFunction

    my $ajaxFunction = $self->ajaxFunction($newValue);

Get or set the value of the I<ajaxFunction> field.

The I<ajaxFunction> is the name of a function to call asynchronously when a new
column is displayed for the first time. The function is run as an instance of
the [[WebPagePm]] object for the current web page. (See above for more details
on how this works.)

=cut

sub ajaxFunction {
    # Get the parameters.
    my ($self, $newValue) = @_;
    # Compute the result.
    return Tracer::GetSet($self, ajaxFunction => $newValue);
}

=head3 metadata

    my $metadata = $self->metadata($newValue);

Get or set the value of the I<metadata> field.

The I<metadata> is a reference to a hash mapping column names to column
definitions. For each column, the definition is a hash containing the following
fields.

=over 4

=item header

Either a string containing the label for the column, or a hash reference
containing a [[TablePm]] column configuration.

=item visible

TRUE if the column should be initially visible, else FALSE.

=item permanent

TRUE if the column show not show up in either list box, else FALSE. This means
that if the column starts hidden, it will stay hidden, and if it starts visible,
it will stay visible.

=item order

A number indicating the display order for the column.

=back

=cut

sub metadata {
    # Get the parameters.
    my ($self, $newValue) = @_;
    # Compute the result.
    return Tracer::GetSet($self, metadata => $newValue);
}

=head3 rowKeyList

    my $rowKeyList = $self->rowKeyList($newValue);

Get or set the value of the I<rowKeyList> field.

The I<rowKeyList> is a reference to a list of the keys for the table rows. It is
only required if an L</ajaxFunction> is specified.

=cut

sub rowKeyList {
    # Get the parameters.
    my ($self, $newValue) = @_;
    # Compute the result.
    return Tracer::GetSet($self, rowKeyList => $newValue);
}

=head3 linkedComponent

    my $linkedComponent = $self->linkedComponent($newValue);

Get or set the value of the I<linkedComponent> field.

This should be a [[TablePm]] object for a table whose display is to be updated
when the column lists are modified. It is only required if an L</ajaxFunction>
is specified.

=cut

sub linkedComponent {
    # Get the parameters.
    my ($self, $newValue) = @_;
    # Compute the result.
    return Tracer::GetSet($self, linkedComponent => $newValue);
}

=head3 parmCache

    my $parmCache = $self->parmCache($newValue);

Get or set the value of the I<parmCache> field.

The I<parmCache> is a string that is made available to the I<ajaxFunction> via
the CGI query parameters.

=cut

sub parmCache {
    # Get the parameters.
    my ($self, $newValue) = @_;
    # Compute the result.
    return Tracer::GetSet($self, parmCache => $newValue);
}

=head3 inCaption

    my $inCaption = $self->inCaption($newValue);

Get or set the value of the I<inCaption> field.

The I<parmCache> is a string that is made available to the I<ajaxFunction> via
the CGI query parameters.

=cut

sub inCaption {
    # Get the parameters.
    my ($self, $newValue) = @_;
    # Compute the result.
    return Tracer::GetSet($self, inCaption => $newValue);
}

=head3 outCaption

    my $outCaption = $self->outCaption($newValue);

Get or set the value of the I<outCaption> field.

This is the caption to display above the left (columns out) box

=cut

sub outCaption {
    # Get the parameters.
    my ($self, $newValue) = @_;
    # Compute the result.
    return Tracer::GetSet($self, outCaption => $newValue);
}

=head3 boxSize

    my $boxSize = $self->boxSize($newValue);

Get or set the value of the I<boxSize> field.

This is the number of rows to display in the list boxes.

=cut

sub boxSize {
    # Get the parameters.
    my ($self, $newValue) = @_;
    # Compute the result.
    return Tracer::GetSet($self, boxSize => $newValue);
}

=head3 inFieldName

    my $inFieldName = $self->inFieldName($newValue);

Get or set the value of the I<inFieldName> field.

If this parameter is specified, a hidden form parameter with the specified name
will be created, and the javascript will maintain as its value a tilde-delimited
list of the IN box's field names when any containing form is submitted.

=cut

sub inFieldName {
    # Get the parameters.
    my ($self, $newValue) = @_;
    # Compute the result.
    return Tracer::GetSet($self, inFieldName => $newValue);
}

1;
