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

#
# seed_running_perl.fragement is the piece of perl code that
# checks to see if the seed server is up, and prints a message and returns
# if it is not.
#
SEED_RUNNING_PERL = seed_running_perl.fragment 

PERLCGISCRIPTS := $(subst .pl,,$(wildcard *.cgi))

PERL_LIB = $(wildcard *.pm) \
	$(wildcard WebPage/*.pm)

WEBPAGES := $(wildcard *.tmpl) \
	$(wildcard images/*.png) \
	$(wildcard images/*.jpeg) \
	$(wildcard css/*.css)

INST_PERL_LIB = $(foreach var, $(PERL_LIB), $(libdir)/$(PKGNAME)/$(var))

all: lib

show:
	@echo cgis $(foreach var, $(PERLCGISCRIPTS), $(cgidir)/$(var))
	@echo top $(TOPDIR)
	@echo pkg $(PKGNAME)
	@echo toolhdr $(TOOL_HDR)
bin:

lib:	$(foreach var, $(PERLCGISCRIPTS), $(cgidir)/$(var)) copy_htaccess $(INST_PERL_LIB) $(foreach var, $(WEBPAGES), $(cgidir)/Html/$(var)) rights

htaccess_src = $(RTROOT)/config/all.htaccess
htaccess_dst = $(cgidir)/.htaccess

copy_htaccess: force
	if test -f $(htaccess_src); then \
		 cp $(htaccess_src) $(htaccess_dst) ; \
	fi

force:

schematools:
stDeclFiles:
stGeneratedFiles:


test:

clean:

$(cgidir)/%: $(TOPDIR)/$(PKGNAME)/% $(TOOL_HDR)
	( cat $(TOOL_HDR) $< > $@; chmod +x $@ )

$(cgidir)/Html/%: $(TOPDIR)/$(PKGNAME)/%
	cp -p $< $(cgidir)/Html/.


#
# We have a config problem at the moment.  I do not want to depend
# upon explicit calls to other packages, as done here nor do I want
# to assume that package was built first.  For now, we live with this.

#$(TOOL_HDR):
#	cd $(workdir); $(TOPDIR)/FigCommon/configure-env $(RTARCH) $(TOPDIR)


#
# Since our lib files have directories, need to create the target
# directory if it doesn't yet exist.
#
$(libdir)/$(PKGNAME)/%.pm: $(TOPDIR)/$(PKGNAME)/%.pm
	tgt_dir=`dirname $@`;  \
	if [ ! -d $$tgt_dir ] ; then \
		mkdir $$tgt_dir; \
	fi
	cp -p  $< $@

rights:
	cd $(TOPDIR)/WebApplication/scripts; \
	perl create_application_rights_module.pl -path $(TOPDIR) -application $(PKGNAME)