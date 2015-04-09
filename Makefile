# Coriolis makefile - because typing on the command line is getting old.

# Configuration for building

NIM = nim
NIMFLAGS = -d:release

# Hacks to make modules easier to deal with building
# todo(blandcr) - make this detect the right extension per platform
MODULEEXT = dll
MODULESRCS = $(wildcard source/modules/*.nim)

MODULEOBJS = $(patsubst %.nim,%.$(MODULEEXT),$(notdir $(MODULESRCS)))

# Targets

all: coriolis modules

coriolis: coriolis.nim
	$(NIM) $(NIMFLAGS) c coriolis.nim

%.$(MODULEEXT) : source/modules/%.nim
	$(NIM) $(NIMFLAGS) -p:source/ --app:lib --nimcache:.//nimcache/ c --o:../../$@ $<

modules: $(MODULEOBJS)

clean:
	rm -rf nimcache
	rm -rf *.$(MODULEEXT)
	rm -rf *.exe

.PHONY:	all
.PHONY:	coriolis
.PHONY:	modules
.PHONY: clean

