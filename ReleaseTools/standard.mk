#######################################################################
# standard.mk
#
# Centralized make rules, macros, etc., shared amongst the packages.
# Package level makefiles do  not define rules, targets, etc.  Instead,
# they define a few macros needed to generate the build lists and
# standard.mk does the rest.
#
# The general pattern is to have "all of a kind" selected by wildcard
# into a build product, e.g., all .c or .cc go into a library or
# all .py get .pyc'd into the install area.  But, there are a few
# macro's that define things to exclude, e.g., .c files that have main()
# and are executables or foo.py files that are top-level programs and
# are to be installed in bin as foo.
#
# A package level makefile does "include standard.mk".  This works because
# of -I's in the Makefile.top in the workdir.  See Makefile.PackageSample.
#
#######################################################################

########################################################################
# Document macros users define in their package level makefiles here:
########################################################################
#
# WEBPAGES    := list of stuff to copy to cgidir/Html. built in bin step
#
# PYTHON_OPEN_CGI := list of py scripts to install as cgi scripts in 
#                 bin step and exclude from py lib list.
#
# CBINS       := foo.c bar.c etc.  List of .c binaries to build. 
#
# CEXCLUDES   := list of .c files, besides $(CBINS), to exclude from the
#                list of C code to build into a .o
#
#
#BINRSCRIPTS = R scripts. installed as script not script.R.
#BINPYSCRIPTS := script1.py etc.  List of py scripts to install in bin.
#                Installed as script1, not script1.py.  Filtered out of
#                python library list (LIBPYFILES)
#BINPERLSCRIPTS := script1.pl etc.  List of perl scripts to install in bin.
#                Installed as script1, not script1.pl.  Filtered out of
#                python library list (LIBPYFILES)
#BINSHSCRIPTS:   List of borne shell scripts to be copied to bin verbatim.
#
#SCHEMATOOLS := file.py, etc.  List of python files defining input to schema
#	        tools.
#
#BINSCRIPTS:     List of scripts to be copied to bin verbatim.
#
#                *** migrate away from BINSCRIPTS!  The extra info that
#                *** its borne shell, py, etc., will let us edit the #! line
#                *** during installation, eventually.
#



########################################################################
# Various lists of things to build
#   implemented via macros above.
########################################################################


LIBPYFILES := $(filter-out $(BINPYSCRIPTS) $(PYTHON_OPEN_CGI) $(SCHEMATOOLS), $(wildcard *.py))
LIBPERLFILES := $(filter-out $(BINPERLSCRIPTS), $(wildcard *.pl))
LIBCFILES := $(foreach var, $(filter-out $(CBINS) $(CEXCLUDES), $(wildcard *.c)), $(libdir)/$(PKGNAME)/$(subst .c,.o,$(var)))


########################################################################
# Package-level makefile Targets
########################################################################

# this follows the all: in Makefile.top, but we drop decouple:, makefile:,
# and installdirs:, because those don't make sense at package level

all: schematools lib bin

bin:	  $(foreach var, $(BINPYSCRIPTS), $(subst .py,,$(bindir)/$(var))) \
	$(foreach var, $(BINRSCRIPTS), $(subst .R,,$(bindir)/$(var))) \
	$(foreach var, $(BINPERLSCRIPTS), $(subst .pl,,$(bindir)/$(var))) \
	$(foreach var, $(BINSHSCRIPTS), $(subst .sh,,$(bindir)/$(var))) \
	$(foreach var, $(BINSCRIPTS), $(bindir)/$(var)) \
	$(foreach var, $(CBINS), $(subst .c,,$(bindir)/$(var))) \
	opencgi webpages

lib:	$(foreach var, $(LIBPYFILES), $(libdir)/$(PKGNAME)/$(var)) $(foreach var, $(LIBPERLFILES), $(libdir)/$(PKGNAME)/$(var)) $(LIBCFILES)

opencgi: $(foreach var, $(PYTHON_OPEN_CGI), $(subst .py,.cgi, $(cgidir)/$(var)))

webpages: $(foreach var, $(WEBPAGES), $(cgidir)/Html/$(var))

schematools: stDeclFiles stGeneratedFiles

stDeclFiles: $(foreach var, $(SCHEMATOOLS), $(libdir)/$(PKGNAME)/$(var))

stGeneratedFiles: $(foreach var, $(subst .py,,$(SCHEMATOOLS)), $(libdir)/$(PKGNAME)Gen/$(var)_st.py) $(foreach var, $(subst .py,,$(SCHEMATOOLS)), $(libdir)/$(PKGNAME)Gen/$(var).sql) $(foreach var, $(subst .py,,$(SCHEMATOOLS)), $(libdir)/$(PKGNAME)Gen/$(var)DbiHandler.py) $(foreach var, $(subst .py,,$(SCHEMATOOLS)), $(libdir)/$(PKGNAME)Gen/$(var)PrimitiveHandler.py)
 
#test:

clean:

########################################################################
# Rules
########################################################################

##
# lib related
##

$(libdir)/$(PKGNAME)/%.o:  $(TOPDIR)/$(PKGNAME)/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(libdir)/$(PKGNAME)/%.py: $(TOPDIR)/$(PKGNAME)/%.py
	cp  $< $@

$(libdir)/$(PKGNAME)/__init__.py: $(TOPDIR)/$(PKGNAME)/__init__.py
	cp  $< $@

$(libdir)/$(PKGNAME)/%.pl: $(TOPDIR)/$(PKGNAME)/%.pl
	cp  $< $@


# verbatim copy from sourcedir to libdir, e.g., py (distutils someday...)
# keep this overly generic one below the more specific py, above.
#
# why is this here??? -ed
$(libdir)/$(PKGNAME)/%: $(TOPDIR)/$(PKGNAME)/%
	cp  $< $@

# generate .py from schematools description of class. (Kah related)

#    Note- add a __init__ dep because everything is required to be a package 
# and so must have an __init__.  putting the dep here is a way to force the
# __init__ to be copied into the dir first so that i can immediately
# be ref'd as a package.  this is needed for schema tools ina way i don't
# grok yet

$(libdir)/$(PKGNAME)Gen/%_st.py: $(TOPDIR)/$(PKGNAME)/%.py  $(libdir)/$(PKGNAME)/__init__.py
	cd $(libdir)/$(PKGNAME); env PYTHONPATH=$(libdir) $(bindir)/generatePy $< > $@

# generate .sql from schematools description of class. (Kah related)
$(libdir)/$(PKGNAME)Gen/%.sql: $(TOPDIR)/$(PKGNAME)/%.py
	cd $(libdir)/$(PKGNAME); env PYTHONPATH=$(libdir) $(bindir)/generateDb $< > $@

# generate object/relational converters from schematools
# description of class. (Kah related)
$(libdir)/$(PKGNAME)Gen/%DbiHandler.py: $(TOPDIR)/$(PKGNAME)/%.py
	$(libdir)/$(PKGNAME); env PYTHONPATH=$(libdir) $(bindir)/generateDbiHandler $< > $@

# generate Primive converters from schematools
# description of class. (Kah related)
$(libdir)/$(PKGNAME)Gen/%PrimitiveHandler.py: $(TOPDIR)/$(PKGNAME)/%.py
	$(libdir)/$(PKGNAME); env PYTHONPATH=$(libdir) $(bindir)/generatePrimitiveHandler $< > $@


## 
# bin related
##

# C excecutables.
$(bindir)/%: $(TOPDIR)/$(PKGNAME)/%.c
	$(CC) $(CFLAGS) -o $@ $< $(wildcard $(libdir)/$(PKGNAME)/*.o)

# python scripts. make script, "foo" from "foo.py".  (rewrite path #! someday)
$(bindir)/%: $(TOPDIR)/$(PKGNAME)/%.py
	cp  $< $@
	chmod 755 $@

# perl scripts. make script, "foo" from "foo.pl".  (rewrite path #! someday)
$(bindir)/%: $(TOPDIR)/$(PKGNAME)/%.pl
	cp  $< $@
	chmod 755 $@

# borne shell scripts

$(bindir)/%: $(TOPDIR)/$(PKGNAME)/%.sh
	cp  $< $@
	chmod 755 $@

# scripts to copy verbatim.
$(bindir)/%: $(TOPDIR)/$(PKGNAME)/%
	cp  $< $@
	chmod 755 $@

##
# cgi related
##

$(cgidir)/Html/%: $(TOPDIR)/$(PKGNAME)/%
	cp $< $(cgidir)/Html/.

$(cgidir)/%.cgi: $(TOPDIR)/$(PKGNAME)/%.py $(TOOL_HDR_PY)
	( cat $(TOOL_HDR_PY) $< > $@; chmod +x $@ )


########################################################################
# Dependency generation
########################################################################
#
# not written yet.  (of all the things not to have...)
#