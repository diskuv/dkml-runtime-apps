(* Cmdliner 1.0 -> 1.1 deprecated a lot of things. But until Cmdliner 1.1
   is in common use in Opam packages we should provide backwards compatibility.
   In fact, Diskuv OCaml is not even using Cmdliner 1.1. *)
[@@@alert "-deprecated"]

open Bos
open Rresult
module Arg = Cmdliner.Arg
module Term = Cmdliner.Term

let setup () =
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
  >>= fun target_platform_name ->
  Dkml_runtimelib.Dkml_environment.set_msys2_entries ~minimize_sideeffects:false
    target_platform_name
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
      Logs.debug (fun m -> m "DKML home directory: %a" Fpath.pp dkmlhome_dir)

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
  let print () = print_endline Dkml_config.version in
  Term.(const print $ const ())

let version_info =
  Term.info ~doc:"Prints the version of the DKML plugin" "version"

let init_t =
  Term.ret
  @@ Term.(
       const rresult_to_term_result
       $ (const Cmd_init.run $ const setup $ localdir_opt_t
        $ Cmd_init.buildtype_t $ yes_t $ Cmd_init.non_system_compiler_t))

let init_info =
  Term.info
    ~doc:
      "Creates or updates an `_opam` subdirectory from zero or more `*.opam` \
       files in the local directory"
    ~man:
      ([
         `P
           "The `_opam` directory, also known as the local Opam switch, holds \
            an OCaml compiler and all of the packages that are specified in \
            the `*.opam` files.";
         `P
           "$(b,--build-type=Release) uses the flamba optimizer described at \
            https://ocaml.org/manual/flambda.html";
       ]
      @
      if Sys.win32 then []
      else
        [
          `P
            "$(b,--build-type=ReleaseCompatPerf) has compatibility with 'perf' \
             monitoring tool. Compatible with Linux only.";
          `P
            "$(b,--build-type=ReleaseCompatFuzz) has compatibility with 'afl' \
             fuzzing tool. Compatible with Linux only.";
        ])
    "init"

let main_t = Term.(ret @@ const (`Help (`Auto, None)))
