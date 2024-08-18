open Rresult
module Arg = Cmdliner.Arg
module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term

let setup () =
  let open Bos in
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

let deprecated_version_cmd =
  let open Dkml_runtimelib.Dkml_cli in
  let old, new_ = ("dkml version", "Ml.Version show") in
  let print () =
    show_we_are_deprecated ~old ~new_;
    print_endline Dkml_runtimelib.version
  in
  let info = Cmd.info ~doc:(deprecated_message ~old ~new_) old in
  let t = Term.(const print $ const ()) in
  Cmd.v info t

let ml_version_show_t =
  let show () = print_endline Dkml_runtimelib.version in
  Term.(const show $ const ())

let ml_version_show_cmd ~description =
  let info =
    Cmd.info ~doc:("Prints the version of " ^ description ^ ".") "show"
  in
  Cmd.v info ml_version_show_t

let ml_version_cmd ~description =
  Cmd.group ~default:ml_version_show_t
    (Cmd.info ~doc:"Shows the version of DkML." "Ml.Version")
    [ ml_version_show_cmd ~description ]

let switch_init_t ~setup =
  Term.ret
    Term.(
      const rresult_to_term_result
      $ (const Cmd_init.run $ Dkml_runtimelib.Dkml_cli.initialized_t
       $ const setup $ localdir_opt_t $ yes_t $ Cmd_init.non_system_compiler_t
       $ Cmd_init.system_only_t $ Cmd_init.enable_imprecise_c99_float_ops_t
       $ Cmd_init.disable_sandboxing_t))

let deprecated_init_cmd =
  let open Dkml_runtimelib.Dkml_cli in
  let old, new_ = ("dkml init", "Ml.Switch init") in
  let info = Cmd.info ~doc:(deprecated_message ~old ~new_) old in
  let setup' () =
    show_we_are_deprecated ~old ~new_;
    setup ()
  in
  Cmd.v info (switch_init_t ~setup:setup')

let switch_init_cmd =
  let info =
    Cmd.info
      ~doc:
        "Creates or updates an `_opam` subdirectory and initializes the system \
         if necessary."
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
  in
  Cmd.v info (switch_init_t ~setup)

let ml_switch_cmd =
  Cmd.group ~default:(switch_init_t ~setup)
    (Cmd.info ~doc:"Create an opam switch." "Ml.Switch")
    [ switch_init_cmd ]

let news_show_t =
  Term.(
    const Dkml_runtimelib.Dkml_news.show
    $ Dkml_runtimelib.Dkml_cli.initialized_t)

let news_show_cmd =
  let info = Cmd.info ~doc:"Show the current DkML news." "show" in
  Cmd.v info news_show_t

let news_maybe_cmd =
  let info =
    Cmd.info
      ~doc:
        "Show the current DkML news if the news has not been shown in a while."
      "maybe"
  in
  let t =
    Term.(
      const Dkml_runtimelib.Dkml_news.show_and_update_if_expired
      $ Dkml_runtimelib.Dkml_cli.initialized_t)
  in
  Cmd.v info t

let news_disable_cmd =
  let info =
    Cmd.info ~doc:"Disable the bi-weekly showing of DkML news." "disable"
  in
  let t =
    Term.(
      const Dkml_runtimelib.Dkml_news.disable
      $ Dkml_runtimelib.Dkml_cli.initialized_t)
  in
  Cmd.v info t

let news_enable_cmd =
  let info =
    Cmd.info ~doc:"Re-enable the bi-weekly showing of DkML news." "enable"
  in
  let t =
    Term.(
      const Dkml_runtimelib.Dkml_news.reenable
      $ Dkml_runtimelib.Dkml_cli.initialized_t)
  in
  Cmd.v info t

let ml_news_cmd =
  Cmd.group ~default:news_show_t
    (Cmd.info ~doc:"Show and enable the DkML news." "Ml.News")
    [ news_show_cmd; news_maybe_cmd; news_disable_cmd; news_enable_cmd ]

let ml_use_cmd =
  let info =
    Cmd.info
      ~man:
        [
          `P "Experimental.";
          `P
            "The command `$(b,dk Ml.Use bash)` will enter a Bash shell. On \
             Windows the Bash shell will come from the MSYS2 project, and MSVC \
             variables will be available.";
        ]
      ~doc:
        "Use C and Unix environments suitable for OCaml within the specified \
         program and arguments."
      "Ml.Use"
  in
  let prog_t =
    Arg.(required & pos 0 (some string) None & info ~doc:"PROGRAM" [])
  in
  let argv1_t =
    Arg.(value & pos_right 0 string [] & info ~doc:"ARGUMENTS" [])
  in
  let t =
    Term.ret
      Term.(
        const rresult_to_term_result
        $ (const (fun (_ : [ `Initialized ]) prog args ->
               (Dkml_runtimelib.Dkml_use.do_use ~mode:`Direct
                  ~argv:(prog :: args)
                  ~extract_dkml_scripts:Dkml_runtimescripts.extract_dkml_scripts)
                 `Initialized)
          $ Dkml_runtimelib.Dkml_cli.initialized_t $ prog_t $ argv1_t))
  in
  Cmd.v info t

let main_t =
  Term.ret
    Term.(
      const (fun (_ : [ `Initialized ]) -> `Help (`Auto, None))
      $ Dkml_runtimelib.Dkml_cli.initialized_t)
