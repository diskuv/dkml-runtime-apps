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

let critical_vsstudio_files =
  Fpath.
    [
      (* Used by [autodetect_vsdev()] in crossplatform-functions.sh *)
      v "Common7" / "Tools" / "VsDevCmd.bat";
    ]

let validate_cached_vsstudio () =
  let* dkml_home_fp = Lazy.force Dkml_context.get_dkmlparenthomedir in
  let txt_fp = Fpath.(dkml_home_fp / "vsstudio.dir.txt") in
  let* txt_exists = OS.File.exists txt_fp in
  if txt_exists then
    let* txt_contents = OS.File.read txt_fp in
    let txt_contents = String.trim txt_contents in
    let* vsstudio_dir_fp = Fpath.of_string txt_contents in
    let* all_critical_files_exist =
      List.fold_right
        (fun critical_fp -> function
          | Error e -> Error e
          | Ok false -> Ok false
          | Ok true -> OS.File.exists Fpath.(vsstudio_dir_fp // critical_fp))
        critical_vsstudio_files (Ok true)
    in
    Ok all_critical_files_exist
  else Ok false

let create_cached_vsstudio ~system_cfg =
  (* Assemble command line arguments *)
  let open Opam_context.SystemConfig in
  let* rel_fp = Fpath.of_string "cache-vsstudio.bat" in
  let cache_vsstudio_fp = Fpath.(system_cfg.scripts_dir_fp // rel_fp) in
  let cmd =
    Cmd.of_list
      (system_cfg.env_exe_wrapper
      @ [
          Fpath.to_string cache_vsstudio_fp;
          "-DkmlPath";
          Fpath.to_string system_cfg.scripts_dir_fp;
        ])
  in
  (* Run the command *)
  run_command cmd rel_fp

let validate_git ~msg_why_check_git ~what_install =
  let* git_exe_opt = OS.Cmd.find_tool Cmd.(v "git") in
  if Option.is_none git_exe_opt then (
    let* has_winget =
      if Sys.win32 then
        let* winget_opt = OS.Cmd.find_tool Cmd.(v "winget") in
        Ok (Option.is_some winget_opt)
      else Ok false
    in
    Logs.warn (fun l ->
        l
          "%s Ordinarily this program would automatically install the %s. \
           However, the Git source control system is required for automatic \
           installation.\n\n\
           SOLUTION:\n\
           1. %s\n\
           2. Re-run this program in a _new_ terminal." msg_why_check_git
          what_install
          (match (Sys.win32, has_winget) with
          | true, true ->
              "Run 'winget install Git.Git' to install Git for Windows."
          | true, false ->
              "Download and install Git for Windows from \
               https://gitforwindows.org/."
          | false, _ ->
              "Use your package manager (ex. 'apt install git' or 'yum install \
               git') to install it."));
    Ok ())
  else Ok ()

let init_system ?enable_imprecise_c99_float_ops ~f_temp_dir ~f_system_cfg () =
  let* temp_dir = f_temp_dir () in
  let* (_created : bool) = OS.Dir.create temp_dir in
  let system_cfg = lazy (f_system_cfg ()) in
  (* [Windows-only] Cache Visual Studio location inside DkML home if necessary *)
  let* ec =
    if Sys.win32 then
      let* validated = validate_cached_vsstudio () in
      if validated then Ok 0
      else (
        Logs.warn (fun l ->
            l
              "Detected that a Visual Studio compatible with DkML has not been \
               located. Locating it now. ETA: 1 minute.");
        let* system_cfg = Lazy.force system_cfg in
        create_cached_vsstudio ~system_cfg)
    else Ok 0
  in
  if ec <> 0 then Ok ec (* short-circuit exit if signal raised *)
  else
    (* Create OCaml system compiler if necessary *)
    let* ocaml_home_fp_opt = Opam_context.SystemConfig.find_ocaml_home () in
    let* ocaml_home_status =
      match ocaml_home_fp_opt with
      | Some ocaml_home_fp -> Ok (Ocaml_home ocaml_home_fp)
      | None ->
          let msg_why =
            "Detected that the system OCaml compiler is not present."
          in
          let* () =
            validate_git ~msg_why_check_git:msg_why
              ~what_install:"system OCaml compiler"
          in
          Logs.warn (fun l -> l "%s Creating it now. ETA: 15 minutes." msg_why);
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
          else
            let msg_why =
              "Detected that the \"opam root\" package cache is not present."
            in
            let* () =
              validate_git ~msg_why_check_git:msg_why
                ~what_install:"\"opam root\" package cache"
            in
            Logs.warn (fun l ->
                l "%s. Creating it now. ETA: 10 minutes." msg_why);
            let* system_cfg = Lazy.force system_cfg in
            create_opam_root ~opamroot_dir_fp ~ocaml_home_fp ~system_cfg
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
