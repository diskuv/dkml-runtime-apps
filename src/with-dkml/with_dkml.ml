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
  (* Why don't we use cmdliner? Because we don't want cmdliner parsing
     the arguments, especially for the zillions of Unix programs where
     the command line arguments will be misinterpreted by cmdliner.

     Ex. `-h` is help for cmdliner but human sortable for `sort`.

     Ex. `dk Ml.Use bash -v` sets the verbose options for Ml.Use, not bash.
     You have to do `dk Ml.Use -- bash -v` to set the verbose option for bash.

     So always use `with-dkml` executable as the **shim** for opam, dune,
     etc. rather than `dk Ml.Use`. For all other uses `dk Ml.Use` is better. *)
  match
    Dkml_runtimelib.Dkml_use.do_use ~mode:`WithDkml
      ~argv:(Array.to_list Sys.argv)
      ~extract_dkml_scripts:Dkml_runtimescripts.extract_dkml_scripts
      `Uninitialized
  with
  | Ok _ -> ()
  | Error (`Msg msg) ->
      prerr_endline ("FATAL: " ^ msg);
      flush stderr;
      flush stdout;
      exit 1
