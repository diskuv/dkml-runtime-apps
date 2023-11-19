open Bos

let ( let* ) = Result.bind

let create_playground_switch ~create_switch_cfg ~opamroot_dir_fp =
  (* Assemble command line arguments *)
  let open Opam_context.CreateSwitchConfig in
  let* rel_fp = Fpath.of_string "vendor/drd/src/unix/create-opam-switch.sh" in
  let create_switch_fp = Fpath.(create_switch_cfg.scripts_dir_fp // rel_fp) in
  let cmd =
    Cmd.of_list
      (create_switch_cfg.env_exe_wrapper
      @ [
          "/bin/sh";
          Fpath.to_string create_switch_fp;
          "-p";
          create_switch_cfg.target_abi;
          "-y";
          "-w";
          "-n";
          "playground";
          "-v";
          Fpath.to_string create_switch_cfg.ocaml_home_fp;
          "-o";
          Fpath.to_string create_switch_cfg.opam_home_fp;
          "-r";
          Fpath.to_string opamroot_dir_fp;
          "-m";
          "conf-withdkml";
        ]
      @ Opam_context.get_msys2_create_opam_switch_options
          create_switch_cfg.msys2_dir_opt)
  in
  Logs.info (fun m -> m "Running command: %a" Cmd.pp cmd);
  (* Run the command in the local directory *)
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

let init_system ~f_temp_dir ~f_create_switch_cfg =
  let* temp_dir = f_temp_dir () in
  let* (_created : bool) = OS.Dir.create temp_dir in
  let* opamroot_dir_fp = Lazy.force Opam_context.get_opam_root in
  (* Create playground switch *)
  let* playground_exists =
    OS.File.exists
      Fpath.(opamroot_dir_fp / "playground" / ".opam-switch" / "switch-state")
  in
  if playground_exists then Ok 0
  else (
    Logs.warn (fun l ->
        l
          "Detected the global [playground] switch is not present. Creating it \
           now. ETA: 5 minutes.");
    let* create_switch_cfg = f_create_switch_cfg () in
    create_playground_switch ~opamroot_dir_fp ~create_switch_cfg)
