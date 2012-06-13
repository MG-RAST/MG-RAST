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
PKGNAME=MGRAST
PERLCGISCRIPTS := $(subst .pl,,$(wildcard *.cgi))

PERL_LIB = $(wildcard *.pm) \
	$(wildcard WebPage/*.pm) \
	$(wildcard OntologyOnDemand/*.pm) \
	$(wildcard JobDB/*.pm) \
	$(wildcard JobDB/*.pm) \
	$(wildcard resources/*.pm)

WEBPAGES := $(wildcard *.tmpl) \
	$(wildcard html/images/*.png) \
	$(wildcard html/images/*.gif) \
	$(wildcard html/images/*.jpg) \
	$(wildcard html/images/*.ico) \
	$(wildcard html/*.html) \
        $(wildcard js/*.js) \
	$(wildcard css/*.css) \
	$(wildcard jar/*.jar)

INST_PERL_LIB = $(foreach var, $(PERL_LIB), $(libdir)/$(PKGNAME)/$(var))

PERL_BIN_SRC := $(wildcard *.pl)
PERL_BIN = $(subst .pl,, $(PERL_BIN_SRC))

all: lib bin

show:
	@echo cgis $(foreach var, $(PERLCGISCRIPTS), $(cgidir)/$(var))
	@echo top $(TOPDIR)
	@echo pkg $(PKGNAME)
	@echo toolhdr $(TOOL_HDR)
bin: $(foreach var, $(PERL_BIN), $(bindir)/$(var))

lib: $(foreach var, $(PERLCGISCRIPTS), $(cgidir)/$(var)) copy_htaccess $(INST_PERL_LIB) $(foreach var, $(WEBPAGES), $(cgidir)/Html/$(var)) rights

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

$(cgidir)/%: $(TOPDIR)/src/$(PKGNAME)/% $(TOOL_HDR)
	( cat $(TOOL_HDR) $< > $@; chmod +x $@ )

$(cgidir)/Html/%: $(TOPDIR)/src/$(PKGNAME)/%
	cp $< $(cgidir)/Html/.

$(bindir)/%: $(TOPDIR)/src/$(PKGNAME)/%.pl $(TOOL_HDR)
	( cat $(TOOL_HDR) $< > $@; chmod +x $@ )


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
$(libdir)/$(PKGNAME)/%.pm: $(TOPDIR)/src/$(PKGNAME)/%.pm
	tgt_dir=`dirname $@`;  \
	if [ ! -d $$tgt_dir ] ; then \
		mkdir $$tgt_dir; \
	fi
	cp  $< $@

rights: