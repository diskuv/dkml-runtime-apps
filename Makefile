all: with-dkml
.PHONY: all

# -------------------------------------
# 	Windows (MSYS2/Cygwin/native) setup
ifeq ($(OS),Windows_NT)
EXEEXT = .exe
else
EXEEXT =
endif
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

# -------------------------------------
# 	DkML / MSYS2 setup
MSYS2_CLANG64_PREREQS =
PACMAN_EXE = $(wildcard /usr/bin/pacman)
CYGPATH_EXE = $(wildcard /usr/bin/cygpath)
OPAMSWITCH := $(CURDIR)
ifneq ($(CYGPATH_EXE),)
ifneq ($(PACMAN_EXE),)
OPAMSWITCH := $(shell $(CYGPATH_EXE) -aw $(CURDIR))
# TODO: UNNECESSARY: libffi and pkg-config required by ctypes, which is required by yaml
MSYS2_CLANG64_PACKAGES = mingw-w64-clang-x86_64-libffi mingw-w64-clang-x86_64-pkg-config
MSYS2_CLANG64_PREREQS = /clang64/bin/pkg-config.exe /clang64/lib/libffi.a
$(MSYS2_CLANG64_PREREQS):
	$(PACMAN_EXE) -S --needed --noconfirm $(MSYS2_CLANG64_PACKAGES)
endif
endif
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

#	[important packages]
#		ocaml.4.14.2: So works with DkML 2.1.1 on Windows
#	[packages that must be pinned as well to propagate into Opam Monorepo .locked files]
#	[edit 1: now unnecessary since no Opam Monorepo .locked files]
#		dune.3.8.3: So works with DkML 2.0.0 on Windows
VERSION_OCAML = 4.14.2
VERSION_DUNE = 3.8.3

SWITCH_ARTIFACTS = _opam/.opam-switch/switch-config
switch: $(SWITCH_ARTIFACTS)
.PHONY: switch
$(SWITCH_ARTIFACTS):
	export OPAMYES=1 && if command -v dkml; then \
		dkml init ; \
	else \
		opam switch create . --formula '["ocaml" {= "$(VERSION_OCAML)"} "dune" {= "$(VERSION_DUNE)"}]' --no-install --repos dune-universe=git+https://github.com/dune-universe/opam-overlays.git,diskuv=git+https://github.com/diskuv/diskuv-opam-repository.git,default; \
	fi

PIN_ARTIFACTS = _opam/.pin.depends
pins: $(PIN_ARTIFACTS)
$(PIN_ARTIFACTS): $(SWITCH_ARTIFACTS) $(MSYS2_CLANG64_PREREQS) Makefile
	export OPAMYES=1 OPAMSWITCH='$(OPAMSWITCH)' && \
	opam pin dune -k version $(VERSION_DUNE) --no-action && \
	touch $@

DUNE_ARTIFACTS = _opam/bin/dune$(EXEEXT)
dune: $(DUNE_ARTIFACTS)
.PHONY: dune
$(DUNE_ARTIFACTS): $(SWITCH_ARTIFACTS) $(MSYS2_CLANG64_PREREQS)
	export OPAMYES=1 OPAMSWITCH='$(OPAMSWITCH)' && \
	opam install dune
	touch $@

IDE_ARTIFACTS = _opam/bin/ocamlformat$(EXEEXT) _opam/bin/ocamlformat-rpc$(EXEEXT) _opam/bin/ocamllsp$(EXEEXT)
ide: $(IDE_ARTIFACTS)
.PHONY: ide
$(IDE_ARTIFACTS): $(SWITCH_ARTIFACTS) $(MSYS2_CLANG64_PREREQS)
	export OPAMYES=1 OPAMSWITCH='$(OPAMSWITCH)' && \
	opam install ocamlformat.0.19.0 ocamlformat-rpc.0.19.0 ocaml-lsp-server
	touch $@

.PHONY: format
format: $(IDE_ARTIFACTS)
	export OPAMYES=1 OPAMSWITCH='$(OPAMSWITCH)' && \
	opam exec -- ocamlformat

# dkml-runtimelib

DKML_RUNTIMELIB_PREREQS = _opam/lib/bos/META _opam/lib/sexplib/META _opam/lib/dkml-c-probe/META
$(DKML_RUNTIMELIB_PREREQS): $(DUNE_ARTIFACTS)
	export OPAMYES=1 OPAMSWITCH='$(OPAMSWITCH)' && \
	opam exec -- dune build --display=short dkml-runtimelib.opam && \
	opam install ./dkml-runtimelib.opam --deps-only --with-test

DKML_RUNTIMELIB_SRC=$(wildcard src/runtimelib/dune src/runtimelib/*.ml src/runtimelib/*.mli)
DKML_RUNTIMELIB_ARTIFACTS = _build/default/src/runtimelib/dkml_runtimelib.cmxs
dkml-runtimelib: $(DKML_RUNTIMELIB_ARTIFACTS)
.PHONY: dkml-runtimelib
$(DKML_RUNTIMELIB_ARTIFACTS): $(DUNE_ARTIFACTS) $(DKML_RUNTIMELIB_PREREQS) $(DKML_RUNTIMELIB_SRC)
	export OPAMYES=1 OPAMSWITCH='$(OPAMSWITCH)' && \
	opam exec -- dune build --display=short -p dkml-runtimelib

# with-dkml (regular opam build)

WITH_DKML_PREREQS = _opam/lib/sha/META _opam/lib/crunch/META
$(WITH_DKML_PREREQS): $(DUNE_ARTIFACTS)
	export OPAMYES=1 OPAMSWITCH='$(OPAMSWITCH)' && \
	opam exec -- dune build --display=short with-dkml.opam && \
	opam install ./dkml-runtimelib.opam ./with-dkml.opam --deps-only --with-test

WITH_DKML_EXE=_build/default/src/with-dkml/with_dkml.exe
WITH_DKML_SRC=$(wildcard src/with-dkml/dune src/with-dkml/*.ml)
with-dkml: $(WITH_DKML_EXE)
.PHONY: with-dkml
$(WITH_DKML_EXE): $(DUNE_ARTIFACTS) $(WITH_DKML_PREREQS) $(WITH_DKML_SRC) $(DKML_RUNTIMELIB_ARTIFACTS)
	export OPAMYES=1 OPAMSWITCH='$(OPAMSWITCH)' && \
	opam exec -- dune build --display=short -p with-dkml,dkml-runtimelib
