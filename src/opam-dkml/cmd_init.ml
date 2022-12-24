open Bos
open Dkml_runtimelib.Monadic_operators
module Arg = Cmdliner.Arg

type buildtype = Debug | Release | ReleaseCompatPerf | ReleaseCompatFuzz

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
  Arg.(value & opt conv_buildtype Debug & info [ "b"; "build-type" ] ~doc ~docv)

let run f_setup localdir_fp_opt buildtype yes non_system_compiler =
  f_setup () >>= fun () ->
  OS.Dir.with_tmp "dkml-scripts-%s"
    (fun dir_fp () ->
      let scripts_dir_fp = Fpath.(dir_fp // v "scripts") in
      let top_dir_fp = Fpath.(dir_fp // v "topdir") in
      (* Find installed dkmlversion.

         Why installed dkmlversion?

         Because when we do 'dkml init' the
         create-opam-switch.sh has to have a versioned opam repository for
         fdopen-mingw in <DKML_home>/repos/<version> ... and that version has
         to exist. Don't assume that just because we compiled opam-dkml.exe
         that the DKML version at compile time (obtainable from
         dkml-runtime-common) will be what is present in <DKML_home>/repos! *)
      Lazy.force Dkml_runtimelib.get_dkmlversion >>= fun dkmlversion ->
      (* Extract all DKML scripts into scripts_dir_fp using installed dkmlversion. *)
      Dkml_runtimescripts.extract_dkml_scripts ~dkmlversion scripts_dir_fp
      >>= fun () ->
      (* Get local directory *)
      Option.fold ~none:(OS.Dir.current ())
        ~some:(fun v -> Ok v)
        localdir_fp_opt
      >>= fun localdir_fp ->
      (* Find env *)
      Fpath.of_string "/" >>= fun slash ->
      (Lazy.force Dkml_runtimelib.get_msys2_dir_opt >>= function
       | None -> Ok Fpath.(slash / "usr" / "bin" / "env")
       | Some msys2_dir ->
           Logs.debug (fun m -> m "MSYS2 directory: %a" Fpath.pp msys2_dir);
           Ok Fpath.(msys2_dir / "usr" / "bin" / "env.exe"))
      >>= fun env_exe ->
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
      (* Set TOPDIR environment variable (why do we still need this?) *)
      OS.Dir.create top_dir_fp >>= fun _existed ->
      OS.Env.set_var "TOPDIR" (Some (Fpath.to_string top_dir_fp)) >>= fun () ->
      (* Assemble command line arguments *)
      Fpath.of_string "vendor/drd/src/unix/create-opam-switch.sh"
      >>= fun rel_fp ->
      let create_switch_fp = Fpath.(scripts_dir_fp // rel_fp) in
      let cmd =
        Cmd.of_list
          ([
             Fpath.to_string env_exe;
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
          Ok (128 + signal))
    ()
  >>= function
  | Ok 0 -> Ok ()
  | Ok signal_exit_code ->
      (* now that we have removed the temporary directory, we can propagate the signal to the caller *)
      exit signal_exit_code
  | Error _ as err -> err
