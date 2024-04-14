# Changes

## 2.1.1

- `src/runtimelib/ocaml_opam_repository_gitref.txt` is used to fix the version
  of the ocaml/opam-repository used during a `dkml init`.

## 2.0.0

- Remove `duniverse/` and opam monorepo Makefile targets since dune+shim
  no longer needs a duniverse build with dune.3.6.2+shim and later

## 1.2.1

- Set OCAMLFIND_CONF and PATH (or LD_LIBRARY_PATH on Unix) for
  `ocaml`, `utop`, `utop-full`, `down` and `ocamlfind` shims
- Remove PATH addition for fswatch from `dune` shim

## 1.0.2

- On `*nix` use `with-dkml` binary rather than `with-dkml.exe`. Same for `dkml-fswatch` which is not
  in use on `*nix` but was changed for consistency.

## 1.0.1

- Split `dkml-runtime` into `dkml-runtimescripts` and `dkml-runtimelib` so `with-dkml.exe` has minimal dependencies
- Remove deprecated `dkml-findup.exe`

## 1.0.0

- Version used alongside Diskuv OCaml 1.0.0. Not published to Opam.
