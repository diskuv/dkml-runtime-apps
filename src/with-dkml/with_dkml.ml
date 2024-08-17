(*
To setup on Unix/macOS:
  eval $(opam env --switch dkml --set-switch)
  # or: eval $(opam env) && opam install dune bos logs fmt sexplib sha
  opam install ocaml-lsp-server ocamlformat ocamlformat-rpc # optional, for vscode or emacs

To setup on Windows, run in MSYS2:
    eval $(opam env --switch "$DiskuvOCamlHome/dkml" --set-switch)

To test DKML_3P_PROGRAM_PATH or DKML_3P_PREFIX_PATH:
    dune build src/with-dkml/with_dkml.exe
    DKML_3P_PROGRAM_PATH='H:/build/windows_x86/vcpkg_installed/x86-windows/debug;H:/build/windows_x86/vcpkg_installed/x86-windows' DKML_3P_PREFIX_PATH='H:/build/windows_x86/vcpkg_installed/x86-windows/debug;H:/build/windows_x86/vcpkg_installed/x86-windows' DKML_BUILD_TRACE=ON DKML_BUILD_TRACE_LEVEL=2 ./_build/default/src/with-dkml/with_dkml.exe sleep 5
*)

let usage_msg = "with-dkml.exe CMD [ARGS...]\n"

let () =
  match
    Dkml_runtimelib.Dkml_use.do_use
      ~extract_dkml_scripts:Dkml_runtimescripts.extract_dkml_scripts ()
  with
  | Ok _ -> ()
  | Error msg ->
      Fmt.pf Fmt.stderr "FATAL: %a@\n" Rresult.R.pp_msg msg;
      exit 1
