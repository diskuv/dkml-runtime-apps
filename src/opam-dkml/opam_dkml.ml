(* Cmdliner 1.0 -> 1.1 deprecated a lot of things. But until Cmdliner 1.1
   is in common use in Opam packages we should provide backwards compatibility.
   In fact, Diskuv OCaml is not even using Cmdliner 1.1. *)
[@@@alert "-deprecated"]

(*
   To setup on Unix/macOS:
     eval $(opam env --switch dkml --set-switch)
     # or: eval $(opam env) && opam install dune bos logs fmt sexplib sha
     opam install ocaml-lsp-server ocamlformat ocamlformat-rpc # optional, for vscode or emacs
   
   To setup on Windows, run in MSYS2:
       eval $(opam env --switch "$DiskuvOCamlHome/dkml" --set-switch)
   
   To test:
       dune build src/opam-dkml/opam_dkml.exe
       DKML_BUILD_TRACE=ON DKML_BUILD_TRACE_LEVEL=2 _build/default/src/opam-dkml/opam_dkml.exe
   
   To install and test:
       opam install ./opam-dkml.opam
       DKML_BUILD_TRACE=ON DKML_BUILD_TRACE_LEVEL=2 opam dkml
*)

open Dkml_exe_lib

let () =
  Cmdliner.Term.exit
  @@ Cmdliner.Term.eval_choice
       (main_t, Cmdliner.Term.info "opam dkml")
       [
         (version_t, version_info ~description:"the DKML plugin");
         (init_t, init_info);
       ]
