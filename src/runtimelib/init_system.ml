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
          "-w";
          "-n";
          "playground";
          (* The playground switch is for the use of teaching OCaml and as such is fully under the ownership
             of DkML. That means no user prompts are required when killing it. In fact, doing a
             [dune build] and having a question posed is a serious violation of user experience _and_
             may break build tooling that expects no user prompts on stdin. *)
          "-y";
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

let create_opam_root ?disable_sandboxing ?reinit ~opamroot_dir_fp ~ocaml_home_fp
    ~system_cfg () =
  (* Assemble command line arguments *)
  let open Opam_context.SystemConfig in
  let* rel_fp =
    Fpath.of_string "vendor/drd/src/unix/private/init-opam-root.sh"
  in
  let init_opam_root_fp = Fpath.(system_cfg.scripts_dir_fp // rel_fp) in
  let disable_sandboxing_args =
    match disable_sandboxing with Some () -> [ "-x" ] | None -> []
  in
  let reinit_args = match reinit with Some () -> [ "-i" ] | None -> [] in
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
          "-c";
          "git+https://github.com/ocaml/opam-repository.git#" ^ Dkml_config.ocaml_opam_repository_gitref;
        ]
      @ disable_sandboxing_args @ reinit_args)
  in
  (* Run the command *)
  run_command cmd rel_fp

type ocamlhome_status =
  | Ocamlhome_valid of Fpath.t
  | Ocamlhome_interrupted of int

let create_ocaml_home_with_compiler ~system_cfg ~enable_imprecise_c99_float_ops
    =
  (* Assemble command line arguments *)
  let open Opam_context.SystemConfig in
  let* rel_fp = Fpath.of_string "install-ocaml-compiler.sh" in
  let* ocaml_git_commit =
    match system_cfg.ocaml_compiler_version with
    | "4.12.1" -> Ok "46c947827ec2f6d6da7fe5e195ae5dda1d2ad0c5"
    | "4.14.0" -> Ok "15553b77175270d987058b386d737ccb939e8d5a"
    | "4.14.2" -> Ok "8eb41f72ded84df884c3671734c947f612091f84"
    | _ ->
        Rresult.R.error_msgf
          "Only 4.12.1, 4.14.0 and 4.14.2 are supported DkML versions, not %s"
          system_cfg.ocaml_compiler_version
  in
  let install_compiler_fp = Fpath.(system_cfg.scripts_dir_fp // rel_fp) in
  let* dkml_home_fp = Lazy.force Dkml_context.get_dkmlhome_dir_or_default in
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
  | Ok 0 -> Ok (Ocamlhome_valid dkml_home_fp)
  | Ok i -> Ok (Ocamlhome_interrupted i)
  | Error e -> Error e

let critical_vsstudio_files =
  Fpath.
    [
      (* Used by [autodetect_vsdev()] in crossplatform-functions.sh *)
      v "Common7" / "Tools" / "VsDevCmd.bat";
    ]

type opamroot_status =
  | Opamroot_missing
  | Opamroot_no_repository
  | Opamroot_complete_with_sandbox
  | Opamroot_complete_without_sandbox

let get_opamroot_status () =
  let* opamroot_dir_fp = Lazy.force Opam_context.get_opam_root in
  let config = Fpath.(opamroot_dir_fp / "config") in
  let* config_exists = OS.File.exists config in
  if config_exists then
    let* dkml_version = Lazy.force Dkml_context.get_dkmlversion_or_default in
    (* COMPLETE: The diskuv-<VERSION> repository must exist *)
    let* diskuv_repo =
      OS.Dir.exists
        Fpath.(
          opamroot_dir_fp / "repo" / Printf.sprintf "diskuv-%s" dkml_version)
    in
    let* diskuv_repo_targz =
      OS.File.exists
        Fpath.(
          opamroot_dir_fp / "repo"
          / Printf.sprintf "diskuv-%s.tar.gz" dkml_version)
    in
    (* Does <opamroot>/config have:
          wrap-build-commands:
            ["%{hooks}%/sandbox.sh" "build"] {os = "linux" | os = "macos"}
          wrap-install-commands:
            ["%{hooks}%/sandbox.sh" "install"] {os = "linux" | os = "macos"}
          wrap-remove-commands:
            ["%{hooks}%/sandbox.sh" "remove"] {os = "linux" | os = "macos"}
    *)
    let* config_contents = OS.File.read config in
    let config_contains_sandbox =
      Astring.String.find_sub ~sub:"%{hooks}%/sandbox.sh" config_contents
      |> Option.is_some
    in
    let state =
      if diskuv_repo || diskuv_repo_targz then
        if config_contains_sandbox then Opamroot_complete_with_sandbox
        else Opamroot_complete_without_sandbox
      else Opamroot_no_repository
    in
    Ok state
  else Ok Opamroot_missing

let is_valid_cached_vsstudio () =
  let* vsstudio_dir_fp_opt = Lazy.force Dkml_context.get_vsstudio_dir_opt in
  match vsstudio_dir_fp_opt with
  | Some vsstudio_dir_fp ->
      let* all_critical_files_exist =
        List.fold_right
          (fun critical_fp -> function
            | Error e -> Error e
            | Ok false -> Ok false
            | Ok true -> OS.File.exists Fpath.(vsstudio_dir_fp // critical_fp))
          critical_vsstudio_files (Ok true)
      in
      Ok all_critical_files_exist
  | None -> Ok false

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

let verify_git ~msg_why_check_git ~what_install =
  let* git_exe_opt = OS.Cmd.find_tool Cmd.(v "git") in
  if Option.is_none git_exe_opt then
    let* has_winget =
      if Sys.win32 then
        let* winget_opt = OS.Cmd.find_tool Cmd.(v "winget") in
        Ok (Option.is_some winget_opt)
      else Ok false
    in
    Rresult.R.error_msgf
      "%s Ordinarily this program would automatically install the %s. However, \
       the Git source control system is required for automatic installation.\n\n\
       SOLUTION:\n\
       1. %s\n\
       2. Re-run this program in a _new_ terminal." msg_why_check_git
      what_install
      (match (Sys.win32, has_winget) with
      | true, true ->
          "Run:\n     winget install Git.Git\n   to install Git for Windows."
      | true, false ->
          "Download and install Git for Windows from \
           https://gitforwindows.org/."
      | false, _ ->
          "Use your package manager (ex. 'apt install git' or 'yum install \
           git') to install it.")
  else Ok ()

(** opam 2.2 prerelease 2022-12-20 (alpha0) does not disable the sandbox
   with --reinit on macOS. So hack is to just kill the statements in the 'config' file. *)
let use_disable_sandbox_hack () = true

let sandbox_statements =
  {|
wrap-build-commands:
  ["%{hooks}%/sandbox.sh" "build"] {os = "linux" | os = "macos"}
wrap-install-commands:
  ["%{hooks}%/sandbox.sh" "install"] {os = "linux" | os = "macos"}
wrap-remove-commands:
  ["%{hooks}%/sandbox.sh" "remove"] {os = "linux" | os = "macos"}
|}

let turn_off_sandboxing ~opamroot_dir_fp ~ocaml_home_fp ~system_cfg =
  if use_disable_sandbox_hack () then (
    let* opamroot_dir_fp = Lazy.force Opam_context.get_opam_root in
    let config = Fpath.(opamroot_dir_fp / "config") in
    let* config_contents = OS.File.read config in
    (* Remove [sandbox_statements] *)
    let new_contents =
      Astring.String.(
        cuts ~sep:sandbox_statements config_contents |> concat ~sep:"")
    in
    let* () = OS.File.write config new_contents in
    Logs.info (fun l -> l "Removed sandbox wrappers from %a" Fpath.pp config);
    Ok 0)
  else
    create_opam_root ~disable_sandboxing:() ~reinit:() ~opamroot_dir_fp
      ~ocaml_home_fp ~system_cfg ()

let create_nativecode_compiler ~system_cfg ~enable_imprecise_c99_float_ops =
  let msg_why =
    "Detected that the system native code OCaml compiler is not present."
  in
  let* () =
    verify_git ~msg_why_check_git:msg_why
      ~what_install:"system native code OCaml compiler"
  in
  Logs.warn (fun l -> l "%s Creating it now. ETA: 15 minutes." msg_why);
  let* system_cfg = Lazy.force system_cfg in
  create_ocaml_home_with_compiler ~system_cfg
    ~enable_imprecise_c99_float_ops:
      (Option.is_some enable_imprecise_c99_float_ops)

let init_nativecode_system_helper ?enable_imprecise_c99_float_ops
    ?disable_sandboxing ~f_system_cfg ~temp_dir () =
  (*

     DEVELOPER NOTE:

       __ALL__ checks must be fast if the system has already been initialized!
       We cannot have the [with-dkml] facade (soon to be "dkml facade") be a
       bottleneck for the underlying executable (opam-real, dune-real, etc.).

       You can:

       - read tiny files or check the presence of files or directory

       Do not:

       - spawn processes
  *)
  let system_cfg = lazy (f_system_cfg ~temp_dir ()) in
  (* [Windows-only] Cache Visual Studio location inside DkML home if necessary *)
  let* ec =
    if Sys.win32 then
      let* validated = is_valid_cached_vsstudio () in
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
    (* Create OCaml native system compiler if necessary *)
    let* ocaml_home_fp_opt = Opam_context.SystemConfig.find_ocaml_home () in
    let* ocaml_home_status =
      match ocaml_home_fp_opt with
      | Some ocaml_home_fp -> (
          let* ocamlopt_fp_opt =
            OS.Cmd.find_tool
              ~search:Fpath.[ ocaml_home_fp / "bin" ]
              (Cmd.v "ocamlopt")
          in
          match ocamlopt_fp_opt with
          | Some _ -> Ok (Ocamlhome_valid ocaml_home_fp)
          | None ->
              create_nativecode_compiler ~system_cfg
                ~enable_imprecise_c99_float_ops)
      | None ->
          create_nativecode_compiler ~system_cfg ~enable_imprecise_c99_float_ops
    in
    match ocaml_home_status with
    | Ocamlhome_interrupted ec ->
        Ok ec (* short-circuit exit if signal raised *)
    | Ocamlhome_valid ocaml_home_fp ->
        (* Create opam root if necessary *)
        let* opamroot_dir_fp = Lazy.force Opam_context.get_opam_root in
        let* opamroot_status = get_opamroot_status () in
        let* ec =
          let what_install = "\"opam root\" package cache" in
          match opamroot_status with
          | Opamroot_complete_without_sandbox -> Ok 0
          | Opamroot_complete_with_sandbox when disable_sandboxing = None ->
              Ok 0
          | Opamroot_missing | Opamroot_no_repository
          | Opamroot_complete_with_sandbox ->
              let msg_why, action, should_turn_off_sandboxing =
                match opamroot_status with
                | Opamroot_no_repository ->
                    ( "Detected that the \"opam root\" package cache is \
                       missing the DkML repository.",
                      "Creating it",
                      false )
                | Opamroot_complete_with_sandbox ->
                    ( "Detected that the \"opam root\" package cache is \
                       configured for sandboxing.",
                      "Disabling sandboxing",
                      true )
                | _ ->
                    ( "Detected that the \"opam root\" package cache is not \
                       present.",
                      "Creating it",
                      false )
              in
              let* () = verify_git ~msg_why_check_git:msg_why ~what_install in
              Logs.warn (fun l ->
                  l "%s %s now. ETA: 10 minutes." msg_why action);
              let* system_cfg = Lazy.force system_cfg in
              if should_turn_off_sandboxing then
                turn_off_sandboxing ~opamroot_dir_fp ~ocaml_home_fp ~system_cfg
              else
                create_opam_root ?disable_sandboxing ~opamroot_dir_fp
                  ~ocaml_home_fp ~system_cfg ()
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

let init_nativecode_system ?enable_imprecise_c99_float_ops ?disable_sandboxing
    ?delete_temp_dir_after_init ~f_temp_dir ~f_system_cfg () =
  let* temp_dir = f_temp_dir () in
  Fun.protect
    ~finally:(fun () ->
      if Option.is_some delete_temp_dir_after_init then
        (* On Windows this could fail because it does not have diskuvbox logic.
           Confer https://github.com/dbuenzli/bos/issues/98 for a problem with
           read-only files like [cache-vsstudio.bat]. *)
        match OS.Dir.delete ~recurse:true temp_dir with
        | Ok () -> ()
        | Error (`Msg msg) ->
            Logs.warn (fun l ->
                l "Deleting the temporary directory %a failed: %s" Fpath.pp
                  temp_dir msg))
    (fun () ->
      let* (_created : bool) = OS.Dir.create temp_dir in
      init_nativecode_system_helper ?enable_imprecise_c99_float_ops
        ?disable_sandboxing ~f_system_cfg ~temp_dir ())
