open Bos
open Dkml_runtimelib.Monadic_operators
module Arg = Cmdliner.Arg

type buildtype = Debug | Release | ReleaseCompatPerf | ReleaseCompatFuzz

let system_only_t =
  let doc =
    "Skip the creation of the `_opam` subdirectory but still initialize the \
     system if it hasn't been initialized."
  in
  Arg.(value & flag & info [ "system" ] ~doc)

let non_system_opt = "non-system-compiler"

let non_system_compiler_t =
  let doc =
    "Create a non-system OCaml compiler unique to the newly created Opam \
     switch rather than re-use the system OCaml compiler. A non-system OCaml \
     compiler must be built from scratch so it will take minutes to compile, \
     but the non-system OCaml compiler can be customized with options not \
     present in the system OCaml compiler."
  in
  Arg.(value & flag & info [ non_system_opt ] ~doc)

let buildtype_t =
  let deprecated =
    "The --build-type option is ignored and will be removed in a future version"
  in
  let doc =
    Fmt.str "%s. Only used when --%s is given."
      (if Sys.win32 then {|$(b,Debug) or $(b,Release)|}
       else
         {|$(b,Debug), $(b,Release), $(b,ReleaseCompatPerf), or $(b,ReleaseCompatFuzz)|})
      non_system_opt
  in
  let docv = "BUILDTYPE" in
  let conv_buildtype =
    if Sys.win32 then Arg.enum [ ("Debug", Debug); ("Release", Release) ]
    else
      Arg.enum
        [
          ("Debug", Debug);
          ("Release", Release);
          ("ReleaseCompatPerf", ReleaseCompatPerf);
          ("ReleaseCompatFuzz", ReleaseCompatFuzz);
        ]
  in
  Arg.(
    value & opt conv_buildtype Release
    & info [ "b"; "build-type" ] ~doc ~docv ~deprecated)

let create_local_switch ~create_switch_cfg ~scripts_dir_fp ~yes
    ~non_system_compiler ~localdir_fp =
  (* Assemble command line arguments *)
  let open Dkml_runtimelib.CreateSwitchConfig in
  Fpath.of_string "vendor/drd/src/unix/create-opam-switch.sh" >>= fun rel_fp ->
  let create_switch_fp = Fpath.(scripts_dir_fp // rel_fp) in
  let cmd =
    Cmd.of_list
      (create_switch_cfg.env_exe_wrapper
      @ [
          "/bin/sh";
          Fpath.to_string create_switch_fp;
          "-p";
          create_switch_cfg.target_abi;
          "-t";
          Fpath.to_string localdir_fp;
          "-o";
          Fpath.to_string create_switch_cfg.opam_home_fp;
          "-m";
          "conf-withdkml";
        ]
      @ (if non_system_compiler then []
         else [ "-v"; Fpath.to_string create_switch_cfg.ocaml_home_fp ])
      @ (if yes then [ "-y" ] else [])
      @ Dkml_runtimelib.get_msys2_create_opam_switch_options
          create_switch_cfg.msys2_dir_opt)
  in
  Logs.info (fun m -> m "Running command: %a" Cmd.pp cmd);
  (* Run the command in the local directory *)
  OS.Cmd.run_status cmd >>= function
  | `Exited 0 -> Ok 0
  | `Exited status ->
      Rresult.R.error_msgf "%a exited with error code %d" Fpath.pp
        Fpath.(v "<builtin>" // rel_fp)
        status
  | `Signaled signal ->
      (* https://stackoverflow.com/questions/1101957/are-there-any-standard-exit-status-codes-in-linux/1535733#1535733 *)
      Ok (128 + signal)

let run f_setup localdir_fp_opt yes non_system_compiler system_only =
  f_setup () >>= fun () ->
  OS.Dir.with_tmp "dkml-scripts-%s"
    (fun dir_fp () ->
      (* Find installed dkmlversion.

         Why installed dkmlversion?

         ORIGINAL: Because when we do 'dkml init' the
         create-opam-switch.sh has to have a versioned opam repository for
         fdopen-mingw in <DKML_home>/repos/<version> ... and that version has
         to exist. Don't assume that just because we compiled dkml.exe
         that the DKML version at compile time (obtainable from
         dkml-runtime-common) will be what is present in <DKML_home>/repos!

         2023-11-18: There is no more fdopen-mingw local versioned opam
         repository, so this dkmlversion may be superfluous now. *)
      Lazy.force Dkml_runtimelib.get_dkmlversion >>= fun dkmlversion ->
      (* Extract all DKML scripts into scripts_dir_fp using installed dkmlversion. *)
      let scripts_dir_fp = Fpath.(dir_fp // v "scripts") in
      Dkml_runtimescripts.extract_dkml_scripts ~dkmlversion scripts_dir_fp
      >>= fun () ->
      (* Get local directory *)
      Option.fold ~none:(OS.Dir.current ())
        ~some:(fun v -> Ok v)
        localdir_fp_opt
      >>= fun localdir_fp ->
      (* Configuration for creating switches *)
      Dkml_runtimelib.CreateSwitchConfig.create ~scripts_dir_fp ()
      >>= fun create_switch_cfg ->
      (* Initialize system if necessary *)
      let f_temp_dir () = Ok Fpath.(dir_fp // v "init-system") in
      let f_create_switch_cfg () = Ok create_switch_cfg in
      Dkml_runtimelib.init_system ~f_temp_dir ~f_create_switch_cfg >>= fun ec ->
      if ec <> 0 then exit ec;
      (* Create local switch *)
      if system_only then Ok 0
      else
        create_local_switch ~create_switch_cfg ~scripts_dir_fp ~yes
          ~non_system_compiler ~localdir_fp)
    ()
  >>= function
  | Ok 0 -> Ok ()
  | Ok signal_exit_code ->
      (* now that we have removed the temporary directory, we can propagate the signal to the caller *)
      exit signal_exit_code
  | Error _ as err -> err
