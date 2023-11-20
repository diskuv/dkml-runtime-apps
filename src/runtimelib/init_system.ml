open Bos

let ( let* ) = Result.bind

let run_command cmd rel_fp =
  Logs.info (fun m -> m "Running command: %a" Cmd.pp cmd);
  let* status = OS.Cmd.run_status cmd in
  match status with
  | `Exited 0 -> Ok 0
  | `Exited status ->
      Rresult.R.error_msgf "%a exited with error code %d" Fpath.pp
        Fpath.(v "<builtin>" // rel_fp)
        status
  | `Signaled signal ->
      (* https://stackoverflow.com/questions/1101957/are-there-any-standard-exit-status-codes-in-linux/1535733#1535733 *)
      Ok (128 + signal)

let create_playground_switch ~system_cfg ~ocaml_home_fp ~opamroot_dir_fp =
  (* Assemble command line arguments *)
  let open Opam_context.SystemConfig in
  let* rel_fp = Fpath.of_string "vendor/drd/src/unix/create-opam-switch.sh" in
  let create_switch_fp = Fpath.(system_cfg.scripts_dir_fp // rel_fp) in
  let cmd =
    Cmd.of_list
      (system_cfg.env_exe_wrapper
      @ [
          "/bin/sh";
          Fpath.to_string create_switch_fp;
          "-p";
          system_cfg.target_abi;
          "-y";
          "-w";
          "-n";
          "playground";
          "-v";
          Fpath.to_string ocaml_home_fp;
          "-o";
          Fpath.to_string system_cfg.opam_home_fp;
          "-r";
          Fpath.to_string opamroot_dir_fp;
          "-m";
          "conf-withdkml";
        ]
      @ Opam_context.get_msys2_create_opam_switch_options system_cfg.msys2)
  in
  (* Run the command *)
  run_command cmd rel_fp

let create_opam_root ~opamroot_dir_fp ~ocaml_home_fp ~system_cfg =
  (* Assemble command line arguments *)
  let open Opam_context.SystemConfig in
  let* rel_fp =
    Fpath.of_string "vendor/drd/src/unix/private/init-opam-root.sh"
  in
  let init_opam_root_fp = Fpath.(system_cfg.scripts_dir_fp // rel_fp) in
  let cmd =
    Cmd.of_list
      (system_cfg.env_exe_wrapper
      @ [
          "/bin/sh";
          Fpath.to_string init_opam_root_fp;
          "-p";
          system_cfg.target_abi;
          "-o";
          Fpath.to_string system_cfg.opam_home_fp;
          "-r";
          Fpath.to_string opamroot_dir_fp;
          "-v";
          Fpath.to_string ocaml_home_fp;
        ])
  in
  (* Run the command *)
  run_command cmd rel_fp

type ocaml_home_status = Ocaml_home of Fpath.t | Signalled of int

let create_ocaml_home_with_compiler ~system_cfg ~enable_imprecise_c99_float_ops
    =
  (* Assemble command line arguments *)
  let open Opam_context.SystemConfig in
  let* rel_fp = Fpath.of_string "install-ocaml-compiler.sh" in
  let* ocaml_git_commit =
    match system_cfg.ocaml_compiler_version with
    | "4.12.1" -> Ok "46c947827ec2f6d6da7fe5e195ae5dda1d2ad0c5"
    | "4.14.0" -> Ok "15553b77175270d987058b386d737ccb939e8d5a"
    | _ ->
        Rresult.R.error_msgf
          "Only 4.12.1 and 4.14.0 are supported DkML versions, not %s"
          system_cfg.ocaml_compiler_version
  in
  let install_compiler_fp = Fpath.(system_cfg.scripts_dir_fp // rel_fp) in
  let* dkml_home_fp = Lazy.force Dkml_context.get_dkmlhome_dir in
  let configure_args =
    if enable_imprecise_c99_float_ops then
      [ "--enable-imprecise-c99-float-ops" ]
    else []
  in
  let cmd =
    Cmd.of_list
      (system_cfg.env_exe_wrapper
      @ [
          "/bin/sh";
          Fpath.to_string install_compiler_fp;
          (* DKMLDIR *)
          Fpath.to_string system_cfg.scripts_dir_fp;
          (* GIT_TAG_OR_COMMIT *)
          ocaml_git_commit;
          (* DKMLHOSTABI *)
          system_cfg.target_abi;
          (* INSTALLDIR *)
          Fpath.to_string dkml_home_fp;
        ]
      @ configure_args)
  in
  (* Run the command *)
  match run_command cmd rel_fp with
  | Ok 0 -> Ok (Ocaml_home dkml_home_fp)
  | Ok i -> Ok (Signalled i)
  | Error e -> Error e

let init_system ?enable_imprecise_c99_float_ops ~f_temp_dir ~f_system_cfg () =
  let* temp_dir = f_temp_dir () in
  let* (_created : bool) = OS.Dir.create temp_dir in
  (* Create OCaml system compiler if necessary *)
  let* ocaml_home_fp_opt = Opam_context.SystemConfig.find_ocaml_home () in
  let system_cfg = lazy (f_system_cfg ()) in
  let* ocaml_home_status =
    match ocaml_home_fp_opt with
    | Some ocaml_home_fp -> Ok (Ocaml_home ocaml_home_fp)
    | None ->
        Logs.warn (fun l ->
            l
              "Detected that the system OCaml compiler is not present. \
               Creating it now. ETA: 15 minutes.");
        let* system_cfg = Lazy.force system_cfg in
        create_ocaml_home_with_compiler ~system_cfg
          ~enable_imprecise_c99_float_ops:
            (Option.is_some enable_imprecise_c99_float_ops)
  in
  match ocaml_home_status with
  | Signalled ec -> Ok ec (* short-circuit exit if signal raised *)
  | Ocaml_home ocaml_home_fp ->
      (* Create opam root if necessary *)
      let* opamroot_dir_fp = Lazy.force Opam_context.get_opam_root in
      let* opamroot_exists =
        OS.File.exists Fpath.(opamroot_dir_fp / "config")
      in
      let* ec =
        if opamroot_exists then Ok 0
        else (
          Logs.warn (fun l ->
              l
                "Detected that the \"opam root\" package cache is not present. \
                 Creating it now. ETA: 10 minutes.");
          let* system_cfg = Lazy.force system_cfg in
          create_opam_root ~opamroot_dir_fp ~ocaml_home_fp ~system_cfg)
      in
      if ec <> 0 then Ok ec (* short-circuit exit if signal raised *)
      else
        (* Create playground switch if necessary *)
        let* playground_exists =
          OS.File.exists
            Fpath.(
              opamroot_dir_fp / "playground" / ".opam-switch" / "switch-state")
        in
        if playground_exists then Ok 0
        else (
          Logs.warn (fun l ->
              l
                "Detected the global [playground] switch is not present. \
                 Creating it now. ETA: 5 minutes.");
          let* system_cfg = Lazy.force system_cfg in
          create_playground_switch ~opamroot_dir_fp ~ocaml_home_fp ~system_cfg)
