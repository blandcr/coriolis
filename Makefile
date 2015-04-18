# Coriolis makefile - because typing on the command line is getting old.

# Configuration for building

NIM = nim
NIMFLAGS = -d:release

# Hacks to make modules easier to deal with building
# todo(blandcr) - make this detect the right extension per platform
MODULEEXT = dll
MODULESRCS = $(wildcard source/modules/*.nim)

MODULEOBJS = $(patsubst %.nim,%.$(MODULEEXT),$(notdir $(MODULESRCS)))

MODULEINCS = source/module_interface.nim

# Targets

all: coriolis modules

coriolis: coriolis.nim
	$(NIM) $(NIMFLAGS) --nimcache:.//build/nimcache c -o:.//build/$@ coriolis.nim

%.$(MODULEEXT) : source/modules/%.nim $(MODULEINCS)
	$(NIM) $(NIMFLAGS) -p:source/ --app:lib --nimcache:.//build/nimcache/ c --o:../../build/$@ $<

modules: $(MODULEOBJS)

clean:
	rm -rf build

.PHONY:	all
.PHONY:	coriolis
.PHONY:	modules
.PHONY: clean

