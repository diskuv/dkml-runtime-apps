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

let create_playground_switch ~system_cfg ~opamroot_dir_fp =
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
          Fpath.to_string system_cfg.ocaml_home_fp;
          "-o";
          Fpath.to_string system_cfg.opam_home_fp;
          "-r";
          Fpath.to_string opamroot_dir_fp;
          "-m";
          "conf-withdkml";
        ]
      @ Opam_context.get_msys2_create_opam_switch_options
          system_cfg.msys2_dir_opt)
  in
  (* Run the command *)
  run_command cmd rel_fp

let create_opam_root ~opamroot_dir_fp ~system_cfg =
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
          Fpath.to_string system_cfg.ocaml_home_fp;
        ])
  in
  (* Run the command *)
  run_command cmd rel_fp

let init_system ~f_temp_dir ~f_system_cfg =
  let* temp_dir = f_temp_dir () in
  let* (_created : bool) = OS.Dir.create temp_dir in
  let* opamroot_dir_fp = Lazy.force Opam_context.get_opam_root in
  (* Create opam root if necessary *)
  let* opamroot_exists = OS.File.exists Fpath.(opamroot_dir_fp / "config") in
  let system_cfg = lazy (f_system_cfg ()) in
  let* ec =
    if opamroot_exists then Ok 0
    else (
      Logs.warn (fun l ->
          l
            "Detected that the \"opam root\" package cache is not present. \
             Creating it now. ETA: 10 minutes.");
      let* system_cfg = Lazy.force system_cfg in
      create_opam_root ~opamroot_dir_fp ~system_cfg)
  in
  if ec <> 0 then Ok ec (* short-circuit exit if signal raised *)
  else
    (* Create playground switch if necessary *)
    let* playground_exists =
      OS.File.exists
        Fpath.(opamroot_dir_fp / "playground" / ".opam-switch" / "switch-state")
    in
    if playground_exists then Ok 0
    else (
      Logs.warn (fun l ->
          l
            "Detected the global [playground] switch is not present. Creating \
             it now. ETA: 5 minutes.");
      let* system_cfg = Lazy.force system_cfg in
      create_playground_switch ~opamroot_dir_fp ~system_cfg)
