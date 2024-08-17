open Cmdliner

let initialized_t =
  let renderer_t = Fmt_cli.style_renderer ~docs:"COMMON OPTIONS" () in
  let logs_t = Logs_cli.level ~docs:"COMMON OPTIONS" () in
  Term.(
    const (fun style_renderer logs ->
        Fmt_tty.setup_std_outputs ?style_renderer ();
        let open Bos in
        let dbt = OS.Env.value "DKML_BUILD_TRACE" OS.Env.string ~absent:"OFF" in
        let dbtl =
          OS.Env.value "DKML_BUILD_TRACE_LEVEL" Dkml_environment.int_parser
            ~absent:0
        in
        (match dbt with
        | "ON" when dbtl >= 2 -> Logs.set_level (Some Logs.Debug)
        | "ON" when dbtl >= 1 -> Logs.set_level (Some Logs.Info)
        | "ON" when dbtl >= 0 -> Logs.set_level (Some Logs.Warning)
        | _ -> Logs.set_level logs);
        Logs.set_reporter (Logs_fmt.reporter ());
        `Initialized)
    $ renderer_t $ logs_t)
