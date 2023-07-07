# Changes

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
