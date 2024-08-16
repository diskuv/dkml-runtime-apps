open Rresult
module Arg = Cmdliner.Arg
module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term

let setup () =
  let open Bos in
  (* Setup logging *)
  Fmt_tty.setup_std_outputs ();
  Logs.set_reporter (Logs_fmt.reporter ());
  let dbt = OS.Env.value "DKML_BUILD_TRACE" OS.Env.string ~absent:"OFF" in
  if
    dbt = "ON"
    && OS.Env.value "DKML_BUILD_TRACE_LEVEL" Dkml_runtimelib.int_parser
         ~absent:0
       >= 2
  then Logs.set_level (Some Logs.Debug)
  else if dbt = "ON" then Logs.set_level (Some Logs.Info)
  else Logs.set_level (Some Logs.Warning);

  (* Setup MSYS2 *)
  Rresult.R.error_to_msg ~pp_error:Fmt.string
    (Dkml_c_probe.C_abi.V2.get_abi_name ())
  >>= fun target_abi ->
  Dkml_runtimelib.Dkml_environment.set_msys2_entries
    ~has_dkml_mutating_ancestor_process:false ~target_abi
  >>= fun () ->
  (* Diagnostics *)
  OS.Env.current () >>= fun current_env ->
  OS.Dir.current () >>= fun current_dir ->
  Logs.debug (fun m ->
      m "Environment:@\n%a" Astring.String.Map.dump_string_map current_env);
  Logs.debug (fun m -> m "Current directory: %a" Fpath.pp current_dir);
  Lazy.force Dkml_runtimelib.get_dkmlhome_dir_opt >>| function
  | None -> ()
  | Some dkmlhome_dir ->
      Logs.debug (fun m -> m "DkML home directory: %a" Fpath.pp dkmlhome_dir)

let rresult_to_term_result = function
  | Ok _ -> `Ok ()
  | Error msg -> `Error (false, Fmt.str "FATAL: %a@\n" Rresult.R.pp_msg msg)

let yes_t =
  let doc = "Answer yes to all interactive yes/no questions" in
  Arg.(value & flag & info [ "y"; "yes" ] ~doc)

let localdir_opt_t =
  let doc =
    "Use the specified local directory rather than the current directory"
  in
  let docv = "LOCALDIR" in
  let conv_fp c =
    let parser v = Arg.conv_parser c v >>= Fpath.of_string in
    let printer v = Fpath.pp v in
    Arg.conv ~docv (parser, printer)
  in
  Arg.(value & opt (some (conv_fp dir)) None & info [ "d"; "dir" ] ~doc ~docv)

let version_t =
  let print () = print_endline Dkml_runtimelib.version in
  Term.(const print $ const ())

let version_info ~description =
  Cmd.info ~doc:("Prints the version of " ^ description) "version"

let init_t =
  Term.ret
  @@ Term.(
       const rresult_to_term_result
       $ (const Cmd_init.run $ const setup $ localdir_opt_t $ yes_t
        $ Cmd_init.non_system_compiler_t $ Cmd_init.system_only_t
        $ Cmd_init.enable_imprecise_c99_float_ops_t
        $ Cmd_init.disable_sandboxing_t))

let init_info =
  Cmd.info
    ~doc:
      "Creates or updates an `_opam` subdirectory and initializes the system \
       if necessary"
    ~man:
      [
        `P
          "The `_opam` directory, also known as the local opam switch, holds \
           an OCaml compiler.";
        `P
          "The system that will be initialized is the OCaml system compiler, \
           the \"opam root\" package cache, and a global `playground` opam \
           switch";
      ]
    "init"

let main_t = Term.(ret @@ const (`Help (`Auto, None)))
