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

package WikiShim;

    use strict;
    use Tracer;
    use CGI;
    use HTML::Template;
    use DBMaster;
    use WebMenu;
    use WebLayout;
    use TWiki::Func;
    use base qw(WebApplication);

=head1 WikiShim Package

Wiki / WebApplication shim

=head2 Introduction

This object embeds a WebApplication page in the wiki. A special template is used
that generates only the interior portion of the HTML. The output from the web
-application page is harvested from the application object and then embedded in
a wiki page.

The object is always called from a REST invocation, so we have access to the
wiki functions. The wiki page is assembled in a normal manner and the
web-application output replaces the text variable.

The fields in this object are as follows.

=over 4

=item cgi

CGI query object used to generate output and access parameters

=item session

TWiki session object

=item application

WebApplication object for this application

=back

=cut

=head3 new

    my $wshim = WikiShim->new(%options);

Construct a new WikiShim object. The following options are supported.

=over 4

=item cgi

CGI object containing the query parameters. If none is provided, one will be created.
This is generally a bad thing, however.

=item application

Name of the web application

=back

=cut

sub new {
    # Get the parameters.
    my ($class, %options) = @_;
    # Get the options.
    my $cgi = $options{cgi} || CGI->new();
    my $applicationID = $options{application} || 'SeedViewer';
    my $defaultPage = $options{default} || 'Home';
    Trace("Wiki shim for $applicationID.") if T(3);
    # Compute the application label. This is "GenomeViewer" for the SEED viewer and is
    # otherwise unaltered.
    my $appName = ($applicationID eq 'SeedViewer' ? 'GenomeViewer' : $applicationID);
    # Create a menu. We don't use the menus, but we don't want WebApplication
    # to fail if the page has custom menus to add.
    my $menu = WebMenu->new();
    # Create the layout object. To do this, we ask the wiki to build a template string for us.
    my $template = TWiki::Func::loadTemplate('view');
    # Get rid of the unneeded meta-variable values.
    $template =~ s/%REVTITLE%//g;
    Trace("Template string is:\n$template") if T(3);
    # Expand it.
    my $raw = TWiki::Func::expandCommonVariables($template, $appName, 'Main');
    # Render it into HTML.
    my $html = TWiki::Func::renderText($raw, 'Main');
    # Clean the nops.
    $html =~ s/<nop>//g;
    # Now we have raw HTML in $html that has the variable "%TEXT%" where the page text is supposed to go.
    # Our first task is to sneak the frame template variables into the header. First, the page title.
    $html =~ s#<title>(.+)</title>#<title><TMPL_VAR NAME="TITLE"></title>#;
    # Next, the style/java/meta stuff.
    my $frameTemplateText = <<____END;
        <TMPL_LOOP NAME=CSS>
        <link rel="stylesheet" type="text/css" href="<TMPL_VAR NAME="CSSFILE">" >
        </TMPL_LOOP>   
        <TMPL_LOOP NAME="JAVASCRIPT">
        <script type="text/javascript" src="<TMPL_VAR NAME="JSFILE">" ></script>
        </TMPL_LOOP>
        <TMPL_LOOP NAME="META">
        <TMPL_VAR NAME="METATAG">
        </TMPL_LOOP>
____END
    $html =~ s#<!-- WebApplicationHeaders -->#$frameTemplateText</head>#;
    # This next trick connects the frame template to the body template.
    $html =~ s/%TEXT%/<TMPL_VAR NAME="BODY">/;
    # We have our frame template. Now we need the body template.
    my $bodyTemplateText = <<____END;
    <TMPL_IF NAME="WARNINGS">
     <div id="warning">
       <TMPL_LOOP NAME="WARNINGS">
        <p class="warning"> <strong> Warning: </strong> <TMPL_VAR NAME="MSG"> </p>
        </TMPL_LOOP>
     </div>
     </TMPL_IF>
     <TMPL_IF NAME="INFO">
     <div id="info">
        <TMPL_LOOP NAME="INFO">
        <p class="info"> <strong> Info: </strong> <TMPL_VAR NAME="MSG"> </p>
        </TMPL_LOOP>
     </div>
     </TMPL_IF>
     <div id="content">
       <TMPL_VAR NAME="CONTENT">
     </div>
____END
    # The two templates enable us to create a layout object.
    my $layout = WebLayout->new({ frame => $html, body => $bodyTemplateText });
    # Tell the layout object we need to fix up links.
    $layout->set_relocation("$FIG_Config::cgi_url/");
    # Create the web-application object. We set noTrace because tracing is already
    # turned on, and we pass the CGI object so that the correct parameters are
    # available.
    my $retVal = WebApplication::new($class,
                                      { id       => $applicationID,
                                        cgi      => $cgi,
                                        noTrace  => 1,
                                        dbmaster => DBMaster->new(-database => $FIG_Config::webapplication_db,
                                                                  -host     => $FIG_Config::webapplication_host,
                                                                  -user     => $FIG_Config::webapplication_user,
                                                                  -password => $FIG_Config::webapplication_password),
                                        menu     =>  $menu,
                                        layout   =>  $layout,
                                        default  => $defaultPage,
                                      } );
    # Denote we're the NMPDR.
    $retVal->page_title_prefix("$appName ");
    $retVal->url("$FIG_Config::cgi_url/wiki/rest.cgi/NmpdrPlugin/$applicationID");
    # Return the object.
    return $retVal;
}


1;
