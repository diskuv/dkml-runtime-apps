all: with-dkml
.PHONY: all

SWITCH_ARTIFACTS = _opam/.opam-switch/switch-config
switch: $(SWITCH_ARTIFACTS)
.PHONY: switch
$(SWITCH_ARTIFACTS):
	export OPAMYES=1 && if [ -x "$$(opam var root)/plugins/bin/opam-dkml" ]; then \
		opam dkml init ; \
	else \
		opam switch create . 4.12.1; \
	fi

# -------------------------------------
# 	Diskuv OCaml / MSYS2 setup
MSYS2_CLANG64_PREREQS =
PACMAN_EXE = $(wildcard /usr/bin/pacman)
CYGPATH_EXE = $(wildcard /usr/bin/cygpath)
OPAMSWITCH := $(CURDIR)
ifneq ($(CYGPATH_EXE),)
ifneq ($(PACMAN_EXE),)
OPAMSWITCH := $(shell $(CYGPATH_EXE) -aw $(CURDIR))
# libffi and pkg-config required by ctypes, which is required by yaml
MSYS2_CLANG64_PACKAGES = mingw-w64-clang-x86_64-libffi mingw-w64-clang-x86_64-pkg-config
MSYS2_CLANG64_PREREQS = /clang64/bin/pkg-config.exe /clang64/lib/libffi.a
$(MSYS2_CLANG64_PREREQS):
	$(PACMAN_EXE) -S --needed --noconfirm $(MSYS2_CLANG64_PACKAGES)
endif
endif
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

DUNE_ARTIFACTS = _opam/bin/dune.exe
dune: $(DUNE_ARTIFACTS)
.PHONY: dune
$(DUNE_ARTIFACTS): $(SWITCH_ARTIFACTS) $(MSYS2_CLANG64_PREREQS)
	export OPAMYES=1 OPAMSWITCH='$(OPAMSWITCH)' && \
	opam install dune

WITH_DKML_EXE=_build/default/src/with-dkml/with_dkml.exe
SRC_DEPS=$(wildcard src/runtime/dune src/runtime/*.ml src/with-dkml/dune src/with-dkml/*.ml)
with-dkml: $(WITH_DKML_EXE)
.PHONY: with-dkml
$(WITH_DKML_EXE): $(DUNE_ARTIFACTS) $(YAML_ARTIFACTS) $(SRC_DEPS)
	export OPAMYES=1 OPAMSWITCH='$(OPAMSWITCH)' && \
	opam exec -- dune exec $(WITH_DKML_EXE)
	touch $@
