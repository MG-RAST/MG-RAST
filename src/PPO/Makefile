#
# Makefile for PPO
#
PKGNAME=PPO
PERLPACKAGES := $(wildcard *.pm) \
		$(wildcard PPOBackend/*.pm)
PERL_BIN_SRC := $(wildcard *.pl)
PERL_BIN = $(subst .pl,, $(PERL_BIN_SRC))

lib: $(foreach var, $(PERLPACKAGES), $(libdir)/$(PKGNAME)/$(var))
bin: $(foreach var, $(PERL_BIN), $(bindir)/$(var))

schematools:
stDeclFiles:
stGeneratedFiles:
test:
clean:

$(libdir)/$(PKGNAME)/%.pm: $(TOPDIR)/src/$(PKGNAME)/%.pm
	tgt_dir=`dirname $@`;  \
	if [ ! -d $$tgt_dir ] ; then \
		mkdir $$tgt_dir; \
	fi
	cp  $< $@

$(libdir)/$(PKGNAME)/%.pm: $(workdir)/%.pm
	cp  $< $@

$(bindir)/%: $(TOPDIR)/src/$(PKGNAME)/%.pl $(TOOL_HDR)
	( cat $(TOOL_HDR) $< > $@; chmod +x $@ )
