(** Create a command line like [".../usr/bin/env.exe"; CMD; ARGS...]
    or ["dune-real.exe"; ARGS...] or ["opam-real.exe"; ARGS...].

    The ["dune-real.exe"; ARGS...] or ["opam-real.exe"; ARGS...] command line
    is chosen when the current executable is named ["dune.exe"] or
    ["opam.exe"], respectively. If you are a distribution maintainer all you
    need to do is rename ["dune.exe"] to ["dune-real.exe"] and
    ["with-dkml.exe"] to ["dune.exe"], and the new ["dune.exe"] will behave
    like the old ["dune.exe"], but will have all the UNIX tools through MSYS
    and the MSVC compiler available to it. The same setup applies to
    ["opam.exe"] as well.

    Otherwise, ["env.exe"] is the executable that is run.
    We use env.exe because it has logic to check if CMD is a shell
    script and run it accordingly (MSYS2 always uses bash for some reason, instead
    of looking at shebang).
*)
let create () =
  let ( let* ) = Rresult.R.( >>= ) in
  let ( let+ ) = Rresult.R.( >>| ) in
  let* slash = Fpath.of_string "/" in
  let* env_exe =
    let* x = Lazy.force Dkml_runtime.get_msys2_dir_opt in
    match x with
    | None -> Rresult.R.ok Fpath.(slash / "usr" / "bin" / "env")
    | Some msys2_dir ->
        Logs.debug (fun m -> m "MSYS2 directory: %a" Fpath.pp msys2_dir);
        Rresult.R.ok Fpath.(msys2_dir / "usr" / "bin" / "env.exe")
  in
  let cmd_and_args = List.tl (Array.to_list Sys.argv) in
  let+ () =
    if [] = cmd_and_args then
      Rresult.R.error_msgf "You need to supply a command, like `%s bash`"
        Bos.OS.Arg.exec
    else Rresult.R.ok ()
  in
  Bos.Cmd.of_list ([ Fpath.to_string env_exe ] @ cmd_and_args)
