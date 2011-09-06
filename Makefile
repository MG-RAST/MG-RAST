########################################################################
# Top level makefile for ReleaseTools.  Will be copied into work 
# directory as Makefile.  Our job here is to define basic environment
# and then iterate over the checked outpackages in the work directory,
# invoking make methods there.  This is one level!  Not recursive.
#
# Ed Frank, Argonne National Laboratory
#   Based upon work of Bob Jacobsen, Lawrence Berkeley National Lab
########################################################################


########################################################################
# The basic environment, macros etc. Our only external environment
# variables are:
#    RTDIST
#    RTARCH
#    RTCURRENT
########################################################################


SHELL = /bin/sh

# these two used to be "if ndef".  why?

export PWD := $(shell pwd)
export TOPDIR := $(shell /bin/pwd)

# expect includes of the form #include "PackageName/item.h"
CPPFLAGS += -I$(PWD)
LDFLAGS += -L$(PWD)/$(RTARCH)/lib
MAKEINCLUDE := -I$(PWD)/ReleaseTools

# this isn't right...should look at rtDist to figure out
# where THIS workdir came from

ifdef RTCURRENT
CPPFLAGS += -I$(RTDIST)/releases/$(RTCURRENT)/$(RTARCH)/include
LDFLAGS += -L$(RTDIST)/releases/$(RTCURRENT)/$(RTARCH)/lib
MAKEINCLUDE += -I$(RTDIST)/releases/$(RTCURRENT)/ReleaseTools
endif

libdir    = $(PWD)/$(RTARCH)/lib
bindir    = $(PWD)/$(RTARCH)/bin
cgidir    = $(PWD)/$(RTARCH)/CGI
workdir   =$(PWD)/$(RTARCH)/tmp
tutdir    = $(PWD)/$(RTARCH)/Tutorial

TOOL_HDR := $(TOPDIR)/$(RTARCH)/tool_hdr
TOOL_HDR_PY := $(TOPDIR)/$(RTARCH)/tool_hdr_py

PACKAGES := $(subst /,, $(dir $(wildcard */Makefile)))

#
# OVERRIDES is a macro passed into children-makes to guide them.
#

OVERRIDES = \
	$(MAKEINCLUDE) \
	TOPDIR=$(TOPDIR) \
	TOOL_HDR=$(PWD)/$(RTARCH)/tool_hdr \
	TOOL_HDR_PY=$(PWD)/$(RTARCH)/tool_hdr_py \
	libdir=$(libdir) \
	bindir=$(bindir) \
	cgidir=$(cgidir) \
	PKGNAME=$(basename $@) \
	CPPFLAGS="$(CPPFLAGS)" \
	LDFLAGS="$(LDFLAGS)" \
	workdir=$(workdir)/$(basename $@) \
	tutdir=$(tutdir)

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

.PHONY: lib bin schematools stDeclFiles stGeneratedFiles clean test purge check_env

# if you change all: make sure all: in standard.mk is consistent.

all: Makefile installdirs decouple schematools lib bin

schematools: stDeclFiles stGeneratedFiles

# The rule is that all the lib targets from the various packages can
# be built in any order.  After that, all teh bins can go, again in
# any order.  But there are a *very few* things that need to be built
# first and perhaps in order.  The decouple: target handles those.
# The $(wildcard foo) trick returns an empty list of foo is not
# present, e.g., the package is not checked out.  This lets the
# decouple target be declared without forcing people to check out
# those packages, i.e., they can just run off the versions in the
# base release.  Thus, decouple is for from-scratch release builds
# and for development of these few, special core packages.

decouple: $(wildcard ReleaseTools) $(wildcard KahDataServices) $(TOOL_HDR) $(TOOL_HDR_PY)

# Use the PACKAGES macro to transform lib, bin, etc., targets
# into package level dependencies, e.g., lib -> PkgA.lib, PkgB.lib
# Rules below then cause PkgA.lib to do a make in PkgaA on lib:

ALL.LIB = check_env $(foreach var,$(PACKAGES),$(var).lib)
lib:  Makefile $(ALL.LIB)

ALL.BIN = check_env $(foreach var,$(PACKAGES),$(var).bin)
bin: Makefile $(ALL.BIN)

ALL.STDECLFILES = check_env $(foreach var,$(PACKAGES),$(var).stDeclFiles)
stDeclFiles: Makefile $(ALL.STDECLFILES)

ALL.STGENERATEDFILES = check_env $(foreach var,$(PACKAGES),$(var).stGeneratedFiles)
stGeneratedFiles: Makefile $(ALL.STGENERATEDFILES)

ALL.TEST = check_env $(foreach var,$(PACKAGES),$(var).test)
test: Makefile $(ALL.TEST)

ALL.CLEAN = check_env $(foreach var,$(PACKAGES),$(var).clean)
#clean: $(ALL.CLEAN)

clean: check_env purge installdirs

purge: check_env
	rm -rf $(RTARCH)/bin $(RTARCH)/lib $(RTARCH)/tmp $(RTARCH)/CGI

check_env: 
ifndef RTARCH
	@echo ""
	@echo "Build environment is not properly configured."
	@echo "Did you source your env.sh ?"
	@echo ""
	@exit 1
endif

##
# Targets to setup the expected directory structure for the
# work directory.  The work directory should be created
# with the mkworkdir command.
###

# If make installdirs is called when no packages are checked out,
# then lib and tmp are not made.  So we add two rules here
# to handle that case.

installdirs: check_env $(libdir) $(bindir) $(cgidir) $(cgidir)/Html $(cgidir)/Html/css $(workdir) $(tutdir)
	- mkdir -p $(tutdir) $(tutdir)/python $(tutdir)/perl
	- mkdir -p $(libdir)
	- mkdir -p $(workdir)
	- mkdir -p $(bindir)
	- mkdir -p $(cgidir)
	- mkdir -p $(cgidir)/Tmp

# the subdirs are for putting python pyc etc. into

$(libdir): $(foreach var,$(PACKAGES),$(libdir)/$(var).installdirs)

$(libdir)/%.installdirs:
	- mkdir -p $(@:.installdirs=)
	- mkdir -p $(@:.installdirs=)Gen
	- touch $(@:.installdirs=)Gen/__init__.py

$(bindir): 
	- mkdir -p $(bindir)

$(cgidir):
	- mkdir $(cgidir)
	- mkdir $(cgidir)/Tmp

$(tutdir):
	- mkdir $(tutdir)
	- mkdir $(tutdir)/python
	- mkdir $(tutdir)/perl

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

%.bin:
	@$(MAKE) -C $(@:.bin=) $(OVERRIDES) bin

%.schematools:
	@$(MAKE) -C $(@:.schematools=) $(OVERRIDES) schematools

%.stDeclFiles:
	@$(MAKE) -C $(@:.stDeclFiles=) $(OVERRIDES) stDeclFiles

%.stGeneratedFiles:
	@$(MAKE) -C $(@:.stGeneratedFiles=) $(OVERRIDES) stGeneratedFiles

%.test:
	@$(MAKE) -C $(@:.test=) $(OVERRIDES) test

%.clean:
	@$(MAKE) -C $(@:.clean=) $(OVERRIDES) clean

# implementation of the decouple: steps that just build whole packages
# the .PHONY here lets us defer to the lib and bin in the package

.PHONY: KahDataServices
KahDataServices:
	# this one we do by hand and a little out of order...
	# we must get bin done here to have the programs that
	# implement schematools target.
	@$(MAKE) -C $(@:.clean=) $(OVERRIDES) lib
	@$(MAKE) -C $(@:.clean=) $(OVERRIDES) bin
	@$(MAKE) -C $(@:.clean=) $(OVERRIDES) schematools

.PHONY: ReleaseTools
ReleaseTools:
	@$(MAKE) -C $(@:.clean=) $(OVERRIDES) all

##
# generation of the tool_header files.  part of decouple
#   these live in $(TOPDIR)/$(RTARCH) but should live
#   in $(libdir).
#
# We use the wildcard trick again so that we have the dependency
# only if ReleaseTools is checked out.  If not checked out, we
# are by definition satisfied with makeScriptHeaders in the base
# release. Note we must make the dependency be on the source file,
# not the $(bindir) file because if the latter does not exist, the
# wildcard fails and there's no dependency!  But if the ReleaseTools/make*
# exists and is newer, then we just defer to the ReleaseTools target
# used above for decouple:
##


$(TOPDIR)/$(RTARCH)/tool_hdr: $(wildcard ReleaseTools/makeScriptHeaders)
	cd $(TOPDIR); $(bindir)/makeScriptHeaders $(TOPDIR)

$(TOPDIR)/$(RTARCH)/tool_hdr_py: $(wildcard ReleaseTools/makeScriptHeaders)
	cd $(TOPDIR); $(bindir)/makeScriptHeaders $(TOPDIR)

ReleaseTools/makeScriptHeaders: ReleaseTools
