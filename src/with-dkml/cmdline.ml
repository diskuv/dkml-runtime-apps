open Bos
open Astring

let is_basename_of_filename_in_search_list ~search_list filename =
  match Fpath.of_string filename with
  | Ok argv0_p ->
      let n = Fpath.filename argv0_p in
      List.mem n search_list
  | Error _ -> false

let is_with_dkml_exe filename =
  let search_list =
    [ "with_dkml"; "with_dkml.exe"; "with-dkml"; "with-dkml.exe" ]
  in
  is_basename_of_filename_in_search_list ~search_list filename

let is_dune_exe path =
  let search_list = [ "dune"; "dune.exe" ] in
  let n = Fpath.filename path in
  List.mem n search_list

let is_opam_exe filename =
  let search_list = [ "opam"; "opam.exe" ] in
  is_basename_of_filename_in_search_list ~search_list filename

let set_dune_env () =
  let ( let* ) = Rresult.R.( >>= ) in
  let dkmlhome = OS.Env.opt_var "DiskuvOCamlHome" ~absent:"" in
  match dkmlhome with
  | "" -> Ok ()
  | _ ->
      let* dkmlhome_p = Fpath.of_string dkmlhome in
      let* path = OS.Env.req_var "PATH" in
      let existing_paths = String.cuts ~empty:false ~sep:";" path in
      let inotify_win_dir = Fpath.(dkmlhome_p / "tools" / "inotify-win") in
      let fswatch_dir = Fpath.(dkmlhome_p / "tools" / "fswatch") in
      let when_exists_add_to_path dir old_path =
        let* dir_exists = OS.Dir.exists dir in
        if dir_exists then
          let entry = Fpath.to_string dir in
          if List.mem entry existing_paths then (
            Logs.debug (fun l ->
                l "Skipping adding pre-existent %a to PATH" Fpath.pp dir);
            Ok old_path)
          else (
            Logs.debug (fun l -> l "Appending %a to PATH" Fpath.pp dir);
            let new_path = old_path ^ ";" ^ entry in
            let* () = OS.Env.set_var "PATH" (Some new_path) in
            Ok new_path)
        else Ok old_path
      in
      let* path = when_exists_add_to_path inotify_win_dir path in
      let* _path = when_exists_add_to_path fswatch_dir path in
      Ok ()

(** Create a command line like [let cmdline_a = [".../usr/bin/env.exe"; Args.others]]
    or [let cmdline_b = ["XYZ-real.exe"; Args.others]]
    or [let cmdline_c = [".../usr/bin/env.exe"; "XYZ-real.exe"; Args.others]].

    We use env.exe because it has logic to check if CMD is a shell
    script and run it accordingly (MSYS2 always uses bash for some reason, instead
    of looking at shebang). And it seems to setup the environment
    so things like the pager (ex. ["opam --help"]) work correctly.

    If the current executable is named ["with-dkml"] or ["with_dkml"], then
    the [cmdline_a] form of the command line is run.

    If the current executable is named ["opam"] and the arguments are of form:
    * [["env"; ...]]
    * [["switch"]]
    * [["switch"; "--some-option"; ...]]
    * [["switch"; "list"; ...]]
    then the [cmdline_b] form of the command line is run.
    Opam will probe the parent process ({!OpamSys.windows_get_shell})
    to discover if the user needs PowerShell, Unix or Command Prompt syntax;
    by not inserting [".../usr/bin/env.exe"] we don't fool Opam into thinking
    we want Unix syntax.

    Otherwise the [cmdline_c] command line is chosen, where the current
    executable is named ["XYZ.exe"]. If you distribute binaries all you
    need to do is rename ["dune.exe"] to ["dune-real.exe"] and
    ["with-dkml.exe"] to ["dune.exe"], and the new ["dune.exe"] will behave
    like the old ["dune.exe"], but will have all the UNIX tools through MSYS
    and the MSVC compiler available to it. You can do the same with
    ["opam.exe"] or any other executable.

    Special case: If the current executable is ["dune"] and the environment
    variable ["DiskuvOCamlHome"] is defined, then
    ["$DiskuvOCamlHome/tools/inotify-win"] and
    ["$DiskuvOCamlHome/tools/fswatch"] are appended to the PATH.
*)
let create_and_setenv_if_necessary () =
  let ( let* ) = Rresult.R.( >>= ) in
  let ( let+ ) = Rresult.R.( >>| ) in
  let* slash = Fpath.of_string "/" in
  let* env_exe =
    let* x = Lazy.force Dkml_runtimelib.get_msys2_dir_opt in
    match x with
    | None -> Ok Fpath.(slash / "usr" / "bin" / "env")
    | Some msys2_dir ->
        Logs.debug (fun m -> m "MSYS2 directory: %a" Fpath.pp msys2_dir);
        Ok Fpath.(msys2_dir / "usr" / "bin" / "env.exe")
  in
  let get_real_exe cmd_no_ext_p =
    let dir, b = Fpath.split_base cmd_no_ext_p in
    let real_p = Fpath.(dir / (filename b ^ "-real")) in
    let+ real_exe_p = OS.Cmd.get_tool (Cmd.v (Fpath.to_string real_p)) in
    real_exe_p
  in
  let get_abs_cmd_and_real_exe cmd =
    Logs.debug (fun l -> l "Desired command is named: %s" cmd);
    (* If the command is not absolute like "dune", then we need to find
       the absolute location of it. *)
    let* abs_cmd_p = OS.Cmd.get_tool (Cmd.v cmd) in
    Logs.debug (fun l -> l "Absolute command path is: %a" Fpath.pp abs_cmd_p);
    let before_ext, ext = Fpath.split_ext abs_cmd_p in
    let cmd_no_ext_p = if ext = ".exe" then before_ext else abs_cmd_p in
    let+ real_exe = get_real_exe cmd_no_ext_p in
    (abs_cmd_p, real_exe)
  in
  let+ cmd_and_args =
    match Array.to_list Sys.argv with
    (* CMDLINE_A FORM *)
    | cmd :: args when is_with_dkml_exe cmd ->
        Ok ([ Fpath.to_string env_exe ] @ args)
    (* CMDLINE_B FORM *)
    | cmd :: "env" :: args when is_opam_exe cmd ->
        Logs.debug (fun l ->
            l
              "Detected [opam env ...] invocation. Not using 'env opam env' so \
               Opam can discover the parent shell");
        let* _abs_cmd_p, real_exe = get_abs_cmd_and_real_exe cmd in
        Ok ([ Fpath.to_string real_exe; "env" ] @ args)
    | [ cmd; "switch" ] when is_opam_exe cmd ->
        Logs.debug (fun l ->
            l
              "Detected [opam switch] invocation. Not using 'env opam switch' \
               so Opam can discover the parent shell");
        let* _abs_cmd_p, real_exe = get_abs_cmd_and_real_exe cmd in
        Ok [ Fpath.to_string real_exe; "switch" ]
    | cmd :: "switch" :: first_arg :: rest_args
      when is_opam_exe cmd
           && String.length first_arg > 2
           && String.is_prefix ~affix:"--" first_arg ->
        Logs.debug (fun l ->
            l
              "Detected [opam switch --some-option ...] invocation. Not using \
               'env opam switch' so Opam can discover the parent shell");
        let* _abs_cmd_p, real_exe = get_abs_cmd_and_real_exe cmd in
        Ok ([ Fpath.to_string real_exe; "switch"; first_arg ] @ rest_args)
    | cmd :: "switch" :: "list" :: args when is_opam_exe cmd ->
        Logs.debug (fun l ->
            l
              "Detected [opam switch list ...] invocation. Not using 'env opam switch' \
               so Opam can discover the parent shell");
        let* _abs_cmd_p, real_exe = get_abs_cmd_and_real_exe cmd in
        Ok ([ Fpath.to_string real_exe; "switch"; "list" ] @ args)
    (* CMDLINE_C FORM *)
    | cmd :: args ->
        let* abs_cmd_p, real_exe = get_abs_cmd_and_real_exe cmd in
        let* () =
          if is_dune_exe abs_cmd_p then (
            Logs.debug (fun l ->
                l
                  "Detected [dune] invocation. Setting Dune environment to \
                   allow 'dune build --watch'");
            set_dune_env ())
          else Ok ()
        in
        Ok ([ Fpath.to_string env_exe; Fpath.to_string real_exe ] @ args)
    | _ ->
        Rresult.R.error_msgf "You need to supply a command, like `%s bash`"
          OS.Arg.exec
  in
  Cmd.of_list cmd_and_args
