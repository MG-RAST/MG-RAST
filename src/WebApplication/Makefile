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
PKGNAME=WebApplication
PERLCGISCRIPTS := $(subst .pl,,$(wildcard *.cgi))

PERL_LIB = $(wildcard *.pm) \
	$(wildcard WebPage/*.pm) \
	$(wildcard WebComponent/*.pm) \
        $(wildcard WebComponent/FormWizard/*.pm) \
	$(wildcard DataHandler/*.pm) \
	$(wildcard WebLayout/*.pm) \
	$(wildcard WebServerBackend/*.pm) \
	$(wildcard WebComments/*.pm) \
	$(wildcard JSON/*.pm)

WEBPAGES := $(wildcard templates/*.tmpl) \
	$(wildcard images/*.png) \
	$(wildcard images/*.gif) \
	$(wildcard images/*.jpg) \
	$(wildcard images/*.jpeg) \
	$(wildcard WebComponent/images/*.png) \
	$(wildcard WebComponent/images/*.gif) \
	$(wildcard WebComponent/images/*.jpg) \
	$(wildcard WebComponent/images/*.jpeg) \
        $(wildcard WebComponent/templates/*.html) \
        $(wildcard WebComponent/templates/*.tmpl) \
	$(wildcard WebComponent/js/*.js) \
	$(wildcard WebComponent/js/*.swf) \
	$(wildcard WebComponent/js/*.css) \
	$(wildcard WebComponent/js/*.htc)

CSS_FILES := \
	$(wildcard css/*.css) \
	$(wildcard WebComponent/css/*.css)

INST_PERL_LIB = $(foreach var, $(PERL_LIB), $(libdir)/$(PKGNAME)/$(var))

INST_WEBPAGES = $(foreach var, $(WEBPAGES), $(cgidir)/Html/$(var)) 
INST_CSS_FILES = $(foreach var, $(CSS_FILE), $(cgidir)/Html/$(var)) 

all: lib

show:
	@echo cgis $(foreach var, $(PERLCGISCRIPTS), $(cgidir)/$(var))
	@echo top $(TOPDIR)
	@echo pkg $(PKGNAME)
	@echo toolhdr $(TOOL_HDR)
bin:

lib:	$(foreach var, $(PERLCGISCRIPTS), $(cgidir)/$(var)) copy_htaccess $(INST_PERL_LIB) $(INST_WEBPAGES) copy_css fix_web_perms

fix_web_perms:
ifneq (,$(findstring public_html, $(cgidir)))
	chmod go-w $(cgidir)
endif

#
# Gross hack.
#
copy_css: $(CSS_FILES)
	for css in $(CSS_FILES); do \
		f=`basename $$css`; \
		cp $$css $(cgidir)/Html/$$f; \
	done

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
ifneq (,$(findstring public_html, $(cgidir)))
	chmod go-w $@
endif

$(cgidir)/Html/%: $(TOPDIR)/src/$(PKGNAME)/%
	cp $< $(cgidir)/Html/.


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

