########################################################################
# Top level makefile for MG-RAST. 
# 
# Jared Wilkening, Argonne National Laboratory
#   Based upon work of: 
#		Bob Jacobsen, Lawrence Berkeley National Lab
#		Ed Frank, Argonne National Laboratory
#		Bob Olson, Argonne National Laboratory
########################################################################


SHELL = /bin/sh

export PWD := $(shell pwd)
export TOPDIR := $(shell /bin/pwd)
TARGET   = site
export TARGETDIR = $(TOPDIR)/$(TARGET)

libdir    = $(TARGETDIR)/lib
bindir    = $(PWD)/bin
cgidir    = $(TARGETDIR)/CGI
workdir   = $(TARGETDIR)/tmp
srcdir    = $(PWD)/src

TOOL_HDR := $(TOPDIR)/$(TARGET)/tool_hdr

PACKAGES := $(subst /,, $(subst $(srcdir)/,, $(dir $(wildcard $(srcdir)/*/Makefile))))

#
# OVERRIDES is a macro passed into children-makes to guide them.
#

OVERRIDES = \
	TOPDIR=$(TOPDIR) \
	TOOL_HDR=$(TOOL_HDR) \
	libdir=$(libdir) \
	bindir=$(bindir) \
	cgidir=$(cgidir)

########################################################################
#
# Targets- these are actually done by the packages, except for
#          a few setup-like things, eg., installdirs.
#
# Note that the behavior of package makefiles is centralized
# into ReleaseTools/standard.mk.  The package makefiles only
# define a few macros to define their needs, whenever possible.
#
########################################################################

.PHONY: lib clean purge 

# if you change all: make sure all: in standard.mk is consistent.

all: installdirs $(TOOL_HDR) lib 
	
# Use the PACKAGES macro to transform lib, bin, etc., targets
# into package level dependencies, e.g., lib -> PkgA.lib, PkgB.lib
# Rules below then cause PkgA.lib to do a make in PkgaA on lib:

ALL.LIB = $(foreach var,$(PACKAGES),$(srcdir)/$(var).lib)
lib:  Makefile $(ALL.LIB)

clean: Makefile purge installdirs

purge: 
	rm -rf $(TARGET)/bin $(TARGET)/lib $(TARGET)/tmp $(TARGET)/CGI


##
# Targets to setup the expected directory structure for the
# work directory.  The work directory should be created
# with the mkworkdir command.
###

# If make installdirs is called when no packages are checked out,
# then lib and tmp are not made.  So we add two rules here
# to handle that case.

installdirs: $(libdir) $(bindir) $(cgidir) $(cgidir)/Html $(cgidir)/Html/css $(workdir) 
	- mkdir -p $(libdir)
	- mkdir -p $(workdir)
	- mkdir -p $(bindir)
	- mkdir -p $(cgidir)

# the subdirs are for putting python pyc etc. into

$(libdir): $(foreach var,$(PACKAGES),$(libdir)/$(var).installdirs)

$(libdir)/%.installdirs:
	- mkdir -p $(@:.installdirs=)
	- mkdir -p $(@:.installdirs=)Gen

$(bindir): 
	- mkdir -p $(bindir)

$(cgidir):
	- mkdir $(cgidir)

$(cgidir)/Html:
	mkdir -p $(cgidir)/Html

$(cgidir)/Html/css:
	mkdir -p $(cgidir)/Html/css

$(workdir): $(foreach var,$(PACKAGES),$(workdir)/$(var).installdirs)

$(workdir)/%.installdirs:
	- mkdir -p $(@:.installdirs=)

########################################################################
# Rules
#
# These rules convert PACKAGENAME.rule into make operations 
# in PACKAGENAME.  Real rules live in standard.mk
########################################################################

%.all:
	@$(MAKE) -C $(@:.lib=) $(OVERRIDES) all

%.lib:
	@$(MAKE) -C $(@:.lib=) $(OVERRIDES) lib

%.clean:
	@$(MAKE) -C $(@:.clean=) $(OVERRIDES) clean

$(libdir)/$(PKGNAME)/%.pl: $(TOPDIR)/$(PKGNAME)/%.pl
	cp  $< $@

$(bindir)/%: $(TOPDIR)/src/$(PKGNAME)/%
	cp  $< $@
	chmod 755 $@

$(cgidir)/Html/%: $(TOPDIR)/src/$(PKGNAME)/%
	cp $< $(cgidir)/Html/.

# implementation of the decouple: steps that just build whole packages
# the .PHONY here lets us defer to the lib and bin in the package

$(TARGETDIR)/tool_hdr: $(wildcard ReleaseTools/makeScriptHeaders)
	cd $(TOPDIR); $(bindir)/makeScriptHeaders $(TOOL_HDR)

