open Bos

let is_with_dkml string_path =
  let wd = [ "with_dkml"; "with_dkml.exe"; "with-dkml"; "with-dkml.exe" ] in
  match Fpath.of_string string_path with
  | Ok argv0_p ->
      let n = Fpath.filename argv0_p in
      List.mem n wd
  | Error _ -> false

(** Create a command line like [".../usr/bin/env.exe"; ARGS...]
    or ["XYZ-real.exe"; ARGS...].

    If the current executable is named ["with-dkml"] or ["with_dkml"], then
    ["env.exe"] is the executable that is run.
    We use env.exe because it has logic to check if CMD is a shell
    script and run it accordingly (MSYS2 always uses bash for some reason, instead
    of looking at shebang).

    Otherwise the ["XYZ-real.exe"; ARGS...] command line
    is chosen, where the current executable is named ["XYZ.exe"]. If you are a
    distribution maintainer all you
    need to do is rename ["dune.exe"] to ["dune-real.exe"] and
    ["with-dkml.exe"] to ["dune.exe"], and the new ["dune.exe"] will behave
    like the old ["dune.exe"], but will have all the UNIX tools through MSYS
    and the MSVC compiler available to it. You can do the same with
    ["opam.exe"] or any other executable.
*)
let create () =
  let ( let* ) = Rresult.R.( >>= ) in
  let ( let+ ) = Rresult.R.( >>| ) in
  let* slash = Fpath.of_string "/" in
  let get_env_exe () =
    let* x = Lazy.force Dkml_runtime.get_msys2_dir_opt in
    match x with
    | None -> Rresult.R.ok Fpath.(slash / "usr" / "bin" / "env")
    | Some msys2_dir ->
        Logs.debug (fun m -> m "MSYS2 directory: %a" Fpath.pp msys2_dir);
        Rresult.R.ok Fpath.(msys2_dir / "usr" / "bin" / "env.exe")
  in
  let get_real_exe cmd_no_ext_p =
    let dir, b = Fpath.split_base cmd_no_ext_p in
    let real_p = Fpath.(dir / (filename b ^ "-real")) in
    let+ real_exe_p = OS.Cmd.get_tool (Cmd.v (Fpath.to_string real_p)) in
    real_exe_p
  in
  let+ cmd_and_args =
    match Array.to_list Sys.argv with
    | cmd :: args when is_with_dkml cmd ->
        let* exe = get_env_exe () in
        Rresult.R.ok ([ Fpath.to_string exe ] @ args)
    | cmd :: args ->
        let* cmd_p = Fpath.of_string cmd in
        let before_ext, ext = Fpath.split_ext cmd_p in
        let cmd_no_ext_p = if ext = ".exe" then before_ext else cmd_p in
        let* exe = get_real_exe cmd_no_ext_p in
        Rresult.R.ok ([ Fpath.to_string exe ] @ args)
    | _ ->
        Rresult.R.error_msgf "You need to supply a command, like `%s bash`"
          OS.Arg.exec
  in
  Cmd.of_list cmd_and_args
