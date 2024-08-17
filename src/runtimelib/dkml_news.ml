module Constants = struct
  let two_weeks = Ptime.Span.of_int_s (60 * 60 * 24 * 7 * 2)
  let forever = Ptime.max
  let pp_ptime = Ptime.pp_human ~tz_offset_s:0 ()
end

module Files = struct
  let xdg_win32, xdg_name = if Sys.win32 then (true, "DkML") else (false, "dkml")
  let xdg = Xdg.create ~env:Sys.getenv_opt ()

  let tstamp =
    let state_dir = Filename.concat (Xdg.state_dir xdg) xdg_name in
    Fpath.(v state_dir / "news.tstamp")
end

module DkNet_Std__Browser = struct
  let open_url_windows (url : Uri.t) : (unit, [ `Msg of string ]) result =
    let open Bos in
    OS.Cmd.run
      Cmd.(v "rundll32" % "url.dll,FileProtocolHandler" % Uri.to_string url)

  let open_url_darwin (url : Uri.t) : (unit, [ `Msg of string ]) result =
    let open Bos in
    OS.Cmd.run Cmd.(v "open" % Uri.to_string url)

  let open_url_linux (url : Uri.t) : (unit, [ `Msg of string ]) result =
    let open Bos in
    OS.Cmd.run Cmd.(v "xdg-open" % Uri.to_string url)

  let open_url ~os (url : Uri.t) : (unit, [ `Msg of string ]) result =
    match os with
    | `Windows -> open_url_windows url
    | `OSX | `IOS -> open_url_darwin url
    | `Linux | _ -> open_url_linux url
end

let show (_ : [ `Initialized ]) =
  let uri =
    (* motd = message of the day *)
    Uri.of_string
      (Printf.sprintf "https://diskuv.com/news/motd/%s" Dkml_config.version)
  in
  let os =
    match Dkml_c_probe.C_abi.V3.get_os () with
    | Error _ -> `Linux
    | Ok UnknownOS -> `Linux
    | Ok Android -> `Linux
    | Ok DragonFly -> `Linux
    | Ok FreeBSD -> `Linux
    | Ok IOS -> `IOS
    | Ok Linux -> `Linux
    | Ok NetBSD -> `Linux
    | Ok OpenBSD -> `Linux
    | Ok OSX -> `OSX
    | Ok Windows -> `Windows
  in
  match DkNet_Std__Browser.open_url ~os uri with
  | Error (`Msg msg) ->
      Logs.debug (fun l ->
          l "Could not open the news page at %a. %s" Uri.pp_hum uri msg)
  | Ok () -> ()

let update (_ : [ `Initialized ]) status =
  let open Bos in
  let now = Ptime_clock.now () in
  match Ptime.add_span now Constants.two_weeks with
  | None -> ()
  | Some expires -> (
      let parent = Fpath.parent Files.tstamp in
      match OS.Dir.create parent with
      | Error (`Msg msg) ->
          Logs.debug (fun l ->
              l
                "News timestamp not updated because the %a directory could not \
                 be created. %s"
                Fpath.pp parent msg)
      | Ok _created -> (
          match
            OS.File.write Files.tstamp (Ptime.to_rfc3339 ~tz_offset_s:0 expires)
          with
          | Error (`Msg msg) ->
              Logs.debug (fun l -> l "News timestamp not updated. %s" msg)
          | Ok () -> (
              match status with
              | `New ->
                  Logs.debug (fun l ->
                      l "Creating news timestamp %a with expiry %a." Fpath.pp
                        Files.tstamp Constants.pp_ptime expires)
              | `Expired ->
                  Logs.debug (fun l ->
                      l "Updated news timestamp %a with new expiry %a." Fpath.pp
                        Files.tstamp Constants.pp_ptime expires))))

let disable (_ : [ `Initialized ]) =
  let open Bos in
  let expires = Constants.forever in
  let parent = Fpath.parent Files.tstamp in
  match OS.Dir.create parent with
  | Error (`Msg msg) ->
      Logs.err (fun l ->
          l
            "News could not be disabled because the %a directory@ could not be \
             created. %s"
            Fpath.pp parent msg)
  | Ok _created -> (
      match
        OS.File.write Files.tstamp (Ptime.to_rfc3339 ~tz_offset_s:0 expires)
      with
      | Error (`Msg msg) -> Logs.debug (fun l -> l "News not disabled.@ %s" msg)
      | Ok () -> Logs.warn (fun l -> l "Disabled news."))

let reenable (_ : [ `Initialized ]) =
  update `Initialized `New;
  Logs.warn (fun l -> l "Re-enabled news.")

let show_and_update_if_expired (_ : [ `Initialized ]) =
  let open Bos in
  Logs.debug (fun l -> l "Checking news timestamp %a" Fpath.pp Files.tstamp);
  match OS.File.exists Files.tstamp with
  | Error (`Msg msg) ->
      Logs.debug (fun l ->
          l "News timestamp could not be checked for existence.@ %s" msg)
  | Ok exists ->
      if exists then
        match OS.File.read Files.tstamp with
        | Error (`Msg msg) ->
            Logs.debug (fun l -> l "News timestamp could not be read.@ %s" msg)
        | Ok content -> (
            match Ptime.of_rfc3339 content with
            | Error (`RFC3339 (_range, err)) ->
                Logs.debug (fun l ->
                    l "News timestamp could not be parsed.@ %a"
                      Ptime.pp_rfc3339_error err);
                update `Initialized `New
            | Ok (expired, _tz, _count) ->
                let now = Ptime_clock.now () in
                if Ptime.is_earlier expired ~than:now then (
                  Logs.debug (fun l ->
                      l "News timestamp expired at %a" Constants.pp_ptime
                        expired);
                  update `Initialized `Expired;
                  show `Initialized)
                else
                  Logs.debug (fun l ->
                      l
                        "Skipping news since the last showing@ will not expire \
                         until %a."
                        Constants.pp_ptime expired))
      else
        (* Does not exist. Create timestamp file. Do _not_ show it so we don't get a user-facing denial of service when update () mostly succeeds but last part repeatedly fails. *)
        update `Initialized `New
