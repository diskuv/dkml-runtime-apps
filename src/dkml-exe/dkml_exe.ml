(*
   To setup on Unix/macOS:
     eval $(opam env --switch dkml --set-switch)
     # or: eval $(opam env) && opam install dune bos logs fmt sexplib sha
     opam install ocaml-lsp-server ocamlformat ocamlformat-rpc # optional, for vscode or emacs
   
   To setup on Windows, run in MSYS2:
       eval $(opam env --switch "$DiskuvOCamlHome/dkml" --set-switch)
   
   To test:
       dune build src/opam-dkml/dkml_exe.exe
       DKML_BUILD_TRACE=ON DKML_BUILD_TRACE_LEVEL=2 _build/default/src/opam-dkml/dkml_exe.exe
   
   To install and test:
       opam install ./dkml-runtimelib.opam ./dkml-exe-lib.opam ./dkml-exe.opam
       DKML_BUILD_TRACE=ON DKML_BUILD_TRACE_LEVEL=2 dkml
*)

open Dkml_exe_lib

let () =
  let open Cmdliner in
  exit
    (Cmd.eval
       (Cmd.group ~default:main_t (Cmd.info "dk")
          [
            deprecated_version_cmd;
            deprecated_init_cmd;
            ml_version_cmd ~description:"DkML command launcher";
            ml_switch_cmd;
            ml_news_cmd;
          ]))
