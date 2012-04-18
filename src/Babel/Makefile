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
PERLCGISCRIPTS := $(subst .pl,,$(wildcard *.cgi))
PKGNAME=Babel
PERL_LIB := $(wildcard */*.pm)

WEBPAGES := $(wildcard *.tmpl) \
	$(wildcard images/*.png) \
	$(wildcard images/*.jpeg) \
	$(wildcard *.js) \
	$(wildcard *.css)

INST_PERL_LIB = $(foreach var, $(PERL_LIB), $(libdir)/$(PKGNAME)/$(var))
INST_PERL_CGI = $(foreach var, $(PERLCGISCRIPTS), $(cgidir)/$(var))

all: lib 

show:
	@echo pkg $(PKGNAME)	
	@echo cgidir $(cgidir)
	@echo pms $(foreach var, $(PERL_LIB), $(libdir)/$(PKGNAME)/$(var))
	@echo cgis $(foreach var, $(PERLCGISCRIPTS), $(cgidir)/$(var))
	@echo top $(TOPDIR)
	@echo toolhdr $(TOOL_HDR)

lib: show $(INST_PERL_LIB) $(INST_PERL_CGI) $(foreach var, $(WEBPAGES), $(cgidir)/Html/$(var)) fix_web_perms

fix_web_perms:
ifneq (,$(findstring public_html, $(cgidir)))
	chmod go-w $(cgidir)
endif

#
# Rules
# 

$(cgidir)/%: $(TOPDIR)/src/$(PKGNAME)/% $(TOOL_HDR)
	( cat $(TOOL_HDR) $< > $@; chmod +x $@ )

$(cgidir)/Html/%: $(TOPDIR)/src/$(PKGNAME)/%
	cp $< $(cgidir)/Html/.

$(libdir)/$(PKGNAME)/%.pm: $(TOPDIR)/src/$(PKGNAME)/%.pm
	tgt_dir=`dirname $@`;  \
	if [ ! -d $$tgt_dir ] ; then \
		mkdir $$tgt_dir; \
	fi
	cp  $< $@

rights:
	cd $(TOPDIR)/src/WebApplication/scripts; \
	perl create_application_rights_module.pl -path $(TOPDIR) -application $(PKGNAME)
