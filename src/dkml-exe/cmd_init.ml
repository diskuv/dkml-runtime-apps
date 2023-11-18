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

let create_local_switch ~scripts_dir_fp ~yes ~env_exe_wrapper ~target_abi
    ~buildtype ~non_system_compiler ~msys2_dir_opt ~localdir_fp ~opam_home_fp
    ~ocaml_home_fp =
  (* Assemble command line arguments *)
  Fpath.of_string "vendor/drd/src/unix/create-opam-switch.sh" >>= fun rel_fp ->
  let create_switch_fp = Fpath.(scripts_dir_fp // rel_fp) in
  let cmd =
    Cmd.of_list
      (env_exe_wrapper
      @ [
          "/bin/sh";
          Fpath.to_string create_switch_fp;
          "-p";
          target_abi;
          "-t";
          Fpath.to_string localdir_fp;
          "-o";
          Fpath.to_string opam_home_fp;
          "-m";
          "conf-withdkml";
        ]
      @ (if non_system_compiler then []
         else [ "-v"; Fpath.to_string ocaml_home_fp ])
      @ (if yes then [ "-y" ] else [])
      @ (match msys2_dir_opt with
        | None -> []
        | Some msys2_dir ->
            (*
             MSYS2 sets PKG_CONFIG_SYSTEM_{INCLUDE,LIBRARY}_PATH which causes
             native Windows pkgconf to not see MSYS2 packages.

             Confer:
             https://github.com/pkgconf/pkgconf#compatibility-with-pkg-config
             https://github.com/msys2/MSYS2-packages/blob/f953d15d0ede1dfb8656a8b3e27c2b694fa1e9a7/filesystem/profile#L54-L55

             Replicated (and need to change if these change):
             [dkml/packaging/version-bump/upsert-dkml-switch.in.sh]
             [dkml-component-ocamlcompiler/assets/staging-files/win32/setup-userprofile.ps1]
          *)
            [
              "-e";
              Fmt.str "PKG_CONFIG_PATH=%a" Fpath.pp
                Fpath.(msys2_dir / "clang64" / "lib" / "pkgconfig");
              "-e";
              "PKG_CONFIG_SYSTEM_INCLUDE_PATH=";
              "-e";
              "PKG_CONFIG_SYSTEM_LIBRARY_PATH=";
            ])
      @
      match buildtype with
      | Debug -> [ "-b"; "Debug" ]
      | Release -> [ "-b"; "Release" ]
      | ReleaseCompatPerf -> [ "-b"; "ReleaseCompatPerf" ]
      | ReleaseCompatFuzz -> [ "-b"; "ReleaseCompatFuzz" ])
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

let run f_setup localdir_fp_opt buildtype yes non_system_compiler system_only =
  f_setup () >>= fun () ->
  OS.Dir.with_tmp "dkml-scripts-%s"
    (fun dir_fp () ->
      let scripts_dir_fp = Fpath.(dir_fp // v "scripts") in
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
      Dkml_runtimescripts.extract_dkml_scripts ~dkmlversion scripts_dir_fp
      >>= fun () ->
      (* Get local directory *)
      Option.fold ~none:(OS.Dir.current ())
        ~some:(fun v -> Ok v)
        localdir_fp_opt
      >>= fun localdir_fp ->
      (* Find optional MSYS2 *)
      Lazy.force Dkml_runtimelib.get_msys2_dir_opt >>= fun msys2_dir_opt ->
      (* Find env *)
      Dkml_runtimelib.Dkml_environment.env_exe_wrapper ()
      >>= fun env_exe_wrapper ->
      (* Find target ABI *)
      Rresult.R.error_to_msg ~pp_error:Fmt.string
        (Dkml_c_probe.C_abi.V2.get_abi_name ())
      >>= fun target_abi ->
      (* Figure out OPAMHOME containing bin/opam *)
      OS.Cmd.get_tool (Cmd.v "opam") >>= fun opam_fp ->
      let opam_bin1_fp, _ = Fpath.split_base opam_fp in
      (if "bin" = Fpath.basename opam_bin1_fp then Ok ()
       else
         Rresult.R.error_msgf "Expected %a to be in a bin/ directory" Fpath.pp
           opam_fp)
      >>= fun () ->
      let opam_home_fp, _ = Fpath.split_base opam_bin1_fp in
      (* Figure out OCAMLHOME containing usr/bin/ocamlc or bin/ocamlc *)
      OS.Cmd.get_tool (Cmd.v "ocamlc") >>= fun ocaml_fp ->
      let ocaml_bin1_fp, _ = Fpath.split_base ocaml_fp in
      (if "bin" = Fpath.basename ocaml_bin1_fp then Ok ()
       else
         Rresult.R.error_msgf "Expected %a to be in a bin/ directory" Fpath.pp
           ocaml_fp)
      >>= fun () ->
      let ocaml_bin2_fp, _ = Fpath.split_base ocaml_bin1_fp in
      let ocaml_bin3_fp, _ = Fpath.split_base ocaml_bin2_fp in
      let ocaml_home_fp =
        if "usr" = Fpath.basename ocaml_bin2_fp then ocaml_bin3_fp
        else ocaml_bin2_fp
      in
      if system_only then Ok 0
      else
        create_local_switch ~scripts_dir_fp ~yes ~env_exe_wrapper ~target_abi
          ~buildtype ~non_system_compiler ~msys2_dir_opt ~localdir_fp
          ~opam_home_fp ~ocaml_home_fp)
    ()
  >>= function
  | Ok 0 -> Ok ()
  | Ok signal_exit_code ->
      (* now that we have removed the temporary directory, we can propagate the signal to the caller *)
      exit signal_exit_code
  | Error _ as err -> err
