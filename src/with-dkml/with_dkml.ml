(*
To setup on Unix/macOS:
  eval $(opam env --switch dkml --set-switch)
  # or: eval $(opam env) && opam install dune bos logs fmt sexplib sha
  opam install ocaml-lsp-server ocamlformat ocamlformat-rpc # optional, for vscode or emacs

To setup on Windows, run in MSYS2:
    eval $(opam env --switch "$DiskuvOCamlHome/dkml" --set-switch)

To test DKML_3P_PROGRAM_PATH or DKML_3P_PREFIX_PATH:
    dune build src/with-dkml/with_dkml.exe
    DKML_3P_PROGRAM_PATH='H:/build/windows_x86/vcpkg_installed/x86-windows/debug;H:/build/windows_x86/vcpkg_installed/x86-windows' DKML_3P_PREFIX_PATH='H:/build/windows_x86/vcpkg_installed/x86-windows/debug;H:/build/windows_x86/vcpkg_installed/x86-windows' DKML_BUILD_TRACE=ON DKML_BUILD_TRACE_LEVEL=2 ./_build/default/src/with-dkml/with_dkml.exe sleep 5
*)
open Bos
open Rresult
open Astring
open Sexplib
open Dkml_runtimelib
open Dkml_runtimelib.Dkml_environment

let usage_msg = "with-dkml.exe CMD [ARGS...]\n"
let crossplatfuncs = Option.get @@ Crossplat.read "crossplatform-functions.sh"

(* [msvc_as_is_vars] is the list of environment variables created by VsDevCmd.bat that
   should always be inserted into the environment as-is.
*)
let msvc_as_is_vars =
  [
    "DevEnvDir";
    "ExtensionSdkDir";
    "Framework40Version";
    "FrameworkDir";
    "Framework64";
    "FrameworkVersion";
    "FrameworkVersion64";
    "INCLUDE";
    "LIB";
    "LIBPATH";
    "UCRTVersion";
    "UniversalCRTSdkDir";
    "VCIDEInstallDir";
    "VCINSTALLDIR";
    "VCToolsInstallDir";
    "VCToolsRedistDir";
    "VCToolsVersion";
    "VisualStudioVersion";
    "VS140COMNTOOLS";
    "VS150COMNTOOLS";
    "VS160COMNTOOLS";
    "VSINSTALLDIR";
    "WindowsLibPath";
    "WindowsSdkBinPath";
    "WindowsSdkDir";
    "WindowsSDKLibVersion";
    "WindowsSdkVerBinPath";
    "WindowsSDKVersion";
  ]

(* [autodetect_compiler_as_is_vars] is the list of environment variables created by autodetect_compiler
   in crossplatform-function.sh that should always be inserted into the environment as-is. *)
let autodetect_compiler_as_is_vars =
  [
    "MSVS_PREFERENCE";
    "CMAKE_GENERATOR_RECOMMENDED";
    "CMAKE_GENERATOR_INSTANCE_RECOMMENDED";
  ]

(** [prune_path_of_microsoft_visual_studio ()] removes all Microsoft Visual Studio entries from the environment
    variable PATH *)
let prune_path_of_microsoft_visual_studio () =
  OS.Env.req_var "PATH" >>= fun path ->
  String.cuts ~empty:false ~sep:";" path
  |> List.filter (fun entry ->
         let contains = path_contains entry in
         let ends_with = path_ends_with entry in
         not
           (ends_with "\\Common7\\IDE"
           || ends_with "\\Common7\\Tools"
           || ends_with "\\MSBuild\\Current\\Bin"
           || contains "\\VC\\Tools\\MSVC\\"
           || contains "\\Windows Kits\\10\\bin\\"
           || contains "\\Microsoft.NET\\Framework64\\"
           || contains "\\MSBuild\\Current\\bin\\"))
  |> fun paths -> Some (String.concat ~sep:";" paths) |> OS.Env.set_var "PATH"

(** [prune_envvar ~f ~path_sep varname] sets the environment variables named [varname] to
   be all the path entries that satisfy the predicate f.
   Path entries are separated from each other by [~path_sep].
   The order of the path entries is preserved.
*)
let prune_envvar ~f ~path_sep varname =
  let varvalue = OS.Env.opt_var varname ~absent:"" in
  if "" = varvalue then R.ok ()
  else
    String.cuts ~empty:false ~sep:path_sep varvalue |> List.filter f
    |> fun entries ->
    Some (String.concat ~sep:path_sep entries) |> OS.Env.set_var varname

(** Remove every MSVC environment variable from the environment and prune MSVC
    entries from the PATH environment variable. *)
let remove_microsoft_visual_studio_entries () =
  (* 1. Remove all as-is variables *)
  List.fold_right
    (fun varname acc ->
      match acc with Ok () -> OS.Env.set_var varname None | Error _ -> acc)
    (msvc_as_is_vars @ autodetect_compiler_as_is_vars)
    (Ok ())
  >>= fun () ->
  (* 2. Remove VSCMD_ variables *)
  OS.Env.current () >>= fun old_env ->
  String.Map.iter
    (fun varname _varvalue ->
      if String.is_prefix ~affix:"VSCMD_" varname then
        OS.Env.set_var varname None |> Rresult.R.error_msg_to_invalid_arg)
    old_env;

  (* 3. Remove MSVC entries from PATH *)
  prune_path_of_microsoft_visual_studio ()

(** [get_dos83_short_path p] gets the DOS 8.3 short form of the path [p],
    if the DOS 8.3 short form exists.

    https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-8dot3name
    controls whether DOS 8.3 short forms exist on a drive ("volume").

    https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-file
    can set a short name on a file (or directory), even if the 8dot3name policy
    has been removed. However this method does not set short names automatically.

    The short form is only available for directories and files that are already
    created.
    *)
let get_dos83_short_path pth =
  let ( let* ) = Result.bind in
  let* cmd_exe = OS.Env.req_var "COMSPEC" in
  (* DOS variable expansion prints the short 8.3 style file name. *)
  OS.Cmd.run_out
    Cmd.(
      v cmd_exe % "/C" % "for" % "%i" % "in" % "("
      (* Fpath, as desired, prints out in Windows (long) format *)
      % Fpath.to_string pth
      % ")" % "do" % "@echo" % "%~si")
  |> OS.Cmd.to_string ~trim:true

(** [set_tempvar_entries] sets TMPDIR on Unix or TEMP on Windows if they need re-adjusting.

  {1 OCaml temporary files}

  When executing an `ocamlc -pp` preprocessor command like
  https://github.com/ocaml/ocaml/blob/77b164c65e7bc8625d0bd79542781952afdd2373/stdlib/Compflags#L18-L20
  (invoked by https://github.com/ocaml/ocaml/blob/77b164c65e7bc8625d0bd79542781952afdd2373/stdlib/Makefile#L201),
  `ocamlc` will use a temporary directory TMPDIR to hold
  the preprocessor output. However for MSYS2 you can get
  a TMPDIR with a space that OCaml 4.12.1 will choke on:
  * `C:\Users\person 1\AppData\Local\Programs\DiskuvOCaml\tools\MSYS2\tmp\ocamlpp87171a`
  * https://gitlab.com/diskuv/diskuv-ocaml/-/issues/13#note_987989664

  Root cause:
  https://github.com/ocaml/ocaml/blob/cce52acc7c7903e92078e9fe40745e11a1b944f0/driver/pparse.ml#L27-L29

  Mitigation:
  > Filename.get_temp_dir_name (https://v2.ocaml.org/api/Filename.html#VALget_temp_dir_name) uses
  > TMPDIR on Unix and TEMP on Windows
  * Make OCaml's temporary directory be the WORK directory
  * Set it to a DOS 8.3 short path like
  `C:\Users\PERSON~1\AppData\Local\Programs\DISKUV~1\...\tmp` on Windows.

  {1 MSVC temporary files}

  TMP must be set or you get
  https://docs.microsoft.com/en-us/cpp/error-messages/tool-errors/command-line-error-d8037?view=msvc-170

  *)
let set_tempvar_entries cache_keys =
  let set_windows_tmp tmpdir =
    (* DOS 8.3 paths can't be printed unless they exist first *)
    OS.Dir.create tmpdir >>= fun _already_existed ->
    (* Use cygpath to get DOS 8.3 path *)
    (* let cygpath =
         Fpath.(msys2_dir / "usr" / "bin" / "cygpath.exe" |> to_string)
       in
       let cmd = Cmd.(v cygpath % "-ad" % Fpath.to_string tmpdir) in
       OS.Cmd.run_out cmd |> OS.Cmd.to_string >>= fun dos83path -> *)
    get_dos83_short_path tmpdir >>= fun dos83path ->
    Logs.debug (fun l -> l "Windows: DOS 8.3 var = %s" dos83path);
    (* Set the TEMP (required for OCaml) and the TMP (required for MSVC) to DOS 8.3 *)
    OS.Env.set_var "TEMP" (Some dos83path) >>= fun () ->
    OS.Env.set_var "TMP" (Some dos83path) >>= fun () ->
    R.ok (dos83path :: dos83path :: cache_keys)
  in
  Lazy.force get_msys2_dir_opt >>= function
  | None ->
      (* On UNIX do not adjust any paths. *)
      R.ok ("" :: "" :: cache_keys)
  | Some msys2_dir -> (
      (* On Windows both TEMP and TMP should be set. If not we can use
         MSYS2 /tmp *)
      match (OS.Env.var "TEMP", OS.Env.var "TMP") with
      | Some temp, None | Some temp, Some _ ->
          Logs.debug (fun l -> l "Windows: 1. Adjusting temp variables");
          set_windows_tmp (Fpath.v temp)
      | None, Some tmp ->
          Logs.debug (fun l -> l "Windows: 2. Adjusting temp variables");
          set_windows_tmp (Fpath.v tmp)
      | None, None ->
          Logs.debug (fun l -> l "Windows: 3. Adjusting temp variables");
          (* Use MSYS2 /tmp dir as a default *)
          set_windows_tmp Fpath.(msys2_dir / "tmp"))

(** [add_microsoft_visual_studio_entries ()] updates the environment to include
   Microsoft Visual Studio entries like LIB, INCLUDE and the others listed in
   [msvc_as_is_vars] and in [autodetect_compiler_as_is_vars]. Additionally PATH is updated.

   The PATH and DiskuvOCamlHome environment variables on entry are used as a cache key.

   If OPAM_SWITCH_PREFIX is not defined, then <dkmlhome_dir>/dkml (the Diskuv
   System opam switch) is used instead.
*)
let set_msvc_entries cache_keys =
  let ( let* ) = Result.bind in
  (* The cache keys will be:

     - DkML home
     - Visual Studio installation directory
     - the PATH on entry to this function (minus any MSVC entries)
  *)
  let* path = OS.Env.req_var "PATH" in
  let dkmlhome = OS.Env.opt_var "DiskuvOCamlHome" ~absent:"" in
  let* vsstudio_dir_opt = Lazy.force Dkml_runtimelib.get_vsstudio_dir_opt in
  let vsstudio_dir_key =
    match vsstudio_dir_opt with
    | Some vsstudio_dir -> Fpath.to_string vsstudio_dir
    | None -> ""
  in
  let cache_keys = path :: vsstudio_dir_key :: dkmlhome :: cache_keys in
  (* 1. Remove MSVC entries *)
  remove_microsoft_visual_studio_entries () >>= fun () ->
  (* 2. Add MSVC entries *)
  Lazy.force get_msys2_dir_opt >>= function
  | None -> R.ok cache_keys
  | Some msys2_dir -> (
      let do_set setvars =
        List.iter
          (fun (varname, varvalue) ->
            if varname = "PATH_COMPILER" then (
              OS.Env.set_var "PATH" (Some (varvalue ^ ";" ^ path))
              |> Rresult.R.error_msg_to_invalid_arg;
              Logs.debug (fun l ->
                  l
                    "Prepending PATH_COMPILER to PATH. (prefix <|> existing) = \
                     (%s <|> %s)"
                    varvalue path))
            else (
              OS.Env.set_var varname (Some varvalue)
              |> Rresult.R.error_msg_to_invalid_arg;
              Logs.debug (fun l ->
                  l "Setting (name,value) = (%s,%s)" varname varvalue)))
          (association_list_of_sexp setvars)
      in
      Lazy.force get_opam_switch_prefix >>= fun opam_switch_prefix ->
      let cache_dir = Fpath.(opam_switch_prefix / ".dkml" / "compiler-cache") in
      let cache_key =
        let ctx = Sha256.init () in
        List.iter (fun key -> Sha256.update_string ctx key) cache_keys;
        Sha256.(finalize ctx |> to_hex)
      in
      let cache_file = Fpath.(cache_dir / (cache_key ^ ".sexp")) in
      OS.File.exists cache_file >>= fun cache_hit ->
      if cache_hit then (
        (* Cache hit *)
        Logs.info (fun l ->
            l "Loading compiler cache entry %a" Fpath.pp cache_file);
        let setvars = Sexp.load_sexp (Fpath.to_string cache_file) in
        do_set setvars;
        Ok cache_keys)
      else
        (* Cache miss *)
        let cache_miss tmpdir () =
          let tmp_sh_file = Fpath.(tmpdir / "d.sh") in
          let tmp_sexp_file = Fpath.(tmpdir / "d.sexp") in
          (* Write the shell script that will autodetect the compiler *)
          OS.File.writef tmp_sh_file "%s@.@.autodetect_compiler --sexp '%a'"
            crossplatfuncs Fpath.pp tmp_sexp_file
          >>= fun () ->
          (* Run the compiler detecting shell script *)
          let dash =
            Fpath.(msys2_dir / "usr" / "bin" / "dash.exe" |> to_string)
          in
          let extra_options =
            match Logs.level () with
            | Some Debug -> Cmd.(v "-x")
            | _ -> Cmd.empty
          in
          let cmd =
            Cmd.(v dash %% extra_options % Fpath.to_string tmp_sh_file)
          in
          (OS.Cmd.run_status cmd >>= function
           | `Exited status ->
               if status <> 0 then
                 Rresult.R.error_msgf
                   "Compiler autodetection failed with exit code %d" status
               else Rresult.R.ok ()
           | `Signaled signal ->
               (* https://stackoverflow.com/questions/1101957/are-there-any-standard-exit-status-codes-in-linux/1535733#1535733 *)
               exit (128 + signal))
          >>| fun () ->
          (* Read the compiler environment variables *)
          let env_vars =
            Sexp.load_sexp_conv_exn
              (Fpath.to_string tmp_sexp_file)
              association_list_of_sexp
          in
          Logs.debug (fun l ->
              l "autodetect_compiler output vars:@\n%a"
                Fmt.(list (Dump.pair string string))
                env_vars);

          (* Store the as-is and PATH_COMPILER compiler environment variables in an association list *)
          let setvars =
            List.filter_map
              (fun varname ->
                match List.assoc_opt varname env_vars with
                | Some varvalue ->
                    Some Sexp.(List [ Atom varname; Atom varvalue ])
                | None -> None)
              ("PATH_COMPILER"
              :: (msvc_as_is_vars @ autodetect_compiler_as_is_vars))
          in
          Sexp.List setvars
        in

        match OS.Dir.with_tmp "withdkml-%s" cache_miss () with
        | Ok (Ok setvars) ->
            do_set setvars;

            (* Save the cache miss so it is a cache hit next time.

               However with high concurrency it is possible to have
               a race condition. On Windows that will appear as a
               [exception Sys_error("Permission denied")] as two
               processes are trying to write to the same file.
               Since this is just a cache, it is fine if we drop it
               (although we should say why!) *)
            OS.Dir.create cache_dir >>= fun _already_exists ->
            Logs.info (fun l ->
                l "Saving compiler cache entry %a" Fpath.pp cache_file);

            (try Sexp.save_hum (Fpath.to_string cache_file) setvars
             with Sys_error _ ->
               (* Sys_error says not to do a literal pattern match. So
                  can't match: Sys_error("Permission denied") *)
               Logs.debug (fun l ->
                   l
                     "Race condition while writing compiler cache entry. \
                      Dropping cache insert"));

            Ok cache_keys
        | Ok (Error _ as err) -> err
        | Error _ as err -> err)

(** [probe_os_path_sep] is a lazy function that looks at the PATH and determines what the PATH
    separator should be.
    We don't use [Sys.win32] except in an edge case, because [Sys.win32] will be true
    even inside MSYS2. Instead if any semicolon is in the PATH then the PATH separator
    must be [";"].
  *)
let probe_os_path_sep =
  lazy
    ( OS.Env.req_var "PATH" >>| fun path ->
      match
        ( String.find (fun c -> c = ';') path,
          String.find (fun c -> c = ':') path )
      with
      | None, None -> if Sys.win32 then ";" else ":"
      | None, Some _ -> ":"
      | Some _, _ -> ";" )

let prune_entries f =
  Lazy.force probe_os_path_sep >>= fun os_path_sep ->
  prune_envvar ~f ~path_sep:";" "INCLUDE" >>= fun () ->
  prune_envvar ~f ~path_sep:os_path_sep "CPATH" >>= fun () ->
  prune_envvar ~f ~path_sep:":" "COMPILER_PATH" >>= fun () ->
  prune_envvar ~f ~path_sep:";" "LIB" >>= fun () ->
  prune_envvar ~f ~path_sep:":" "LIBRARY_PATH" >>= fun () ->
  prune_envvar ~f ~path_sep:os_path_sep "PKG_CONFIG_PATH" >>= fun () ->
  prune_envvar ~f ~path_sep:os_path_sep "PATH"

let prepend_envvar ~path_sep varname dir = function
  | None -> OS.Env.set_var varname (Some dir)
  | Some v when "" = v -> OS.Env.set_var varname (Some dir)
  | Some v -> OS.Env.set_var varname (Some (dir ^ path_sep ^ v))

let prepend_entries ~tools installed_dir =
  Lazy.force probe_os_path_sep >>= fun os_path_sep ->
  let include_dir = Fpath.(installed_dir / "include" |> to_string) in
  OS.Env.parse "INCLUDE" OS.Env.(some string) ~absent:None
  >>= prepend_envvar ~path_sep:";" "INCLUDE" include_dir
  >>= fun () ->
  OS.Env.parse "CPATH" OS.Env.(some string) ~absent:None
  >>= prepend_envvar ~path_sep:os_path_sep "CPATH" include_dir
  >>= fun () ->
  OS.Env.parse "COMPILER_PATH" OS.Env.(some string) ~absent:None
  >>= prepend_envvar ~path_sep:":" "COMPILER_PATH" include_dir
  >>= fun () ->
  let lib_dir = Fpath.(installed_dir / "lib" |> to_string) in
  OS.Env.parse "LIB" OS.Env.(some string) ~absent:None
  >>= prepend_envvar ~path_sep:";" "LIB" lib_dir
  >>= fun () ->
  OS.Env.parse "LIBRARY_PATH" OS.Env.(some string) ~absent:None
  >>= prepend_envvar ~path_sep:":" "LIBRARY_PATH" lib_dir
  >>= fun () ->
  OS.Env.parse "PKG_CONFIG_PATH" OS.Env.(some string) ~absent:None
  >>= prepend_envvar ~path_sep:os_path_sep "PKG_CONFIG_PATH"
        Fpath.(installed_dir / "lib" / "pkgconfig" |> to_string)
  >>= fun () ->
  (if tools then
     OS.Path.query Fpath.(installed_dir / "tools" / "$(tool)" / "$(file).exe")
     >>= fun matches ->
     R.ok
       (List.map (fun (_fp, pat) -> Astring.String.Map.get "tool" pat) matches)
     >>= fun tools_with_exe ->
     OS.Path.query Fpath.(installed_dir / "tools" / "$(tool)" / "$(file).dll")
     >>= fun matches ->
     R.ok
       (List.map (fun (_fp, pat) -> Astring.String.Map.get "tool" pat) matches)
     >>| fun tools_with_dll ->
     List.sort_uniq String.compare (tools_with_exe @ tools_with_dll)
   else R.ok [])
  >>= fun uniq_tools ->
  let installed_path =
    Fpath.(installed_dir / "bin" |> to_string)
    ^ List.fold_left
        (fun acc b ->
          acc ^ os_path_sep ^ Fpath.(installed_dir / "tools" / b |> to_string))
        "" uniq_tools
  in
  OS.Env.parse "PATH" OS.Env.(some string) ~absent:None
  >>= prepend_envvar ~path_sep:os_path_sep "PATH" installed_path

(* [set_3p_prefix_entries cache_keys] will modify MSVC/GCC/clang variables and PKG_CONFIG_PATH and PATH for
    each directory in the semicolon-separated environment variable DKML_3P_PREFIX_PATH.

   The CPATH, COMPILER_PATH, INCLUDE, LIBRARY_PATH, and LIB variables are modified so that
   when:

   - MSVC is used INCLUDE and LIB are picked up
     (https://docs.microsoft.com/en-us/cpp/build/reference/cl-environment-variables?view=msvc-160
     and https://docs.microsoft.com/en-us/cpp/build/reference/linking?view=msvc-160#link-environment-variables)
   - GCC is used COMPILER_PATH and LIBRARY_PATH are picked up
     (https://gcc.gnu.org/onlinedocs/gcc/Environment-Variables.html#Environment-Variables)
   - clang is used CPATH and LIBRARY_PATH are picked up
     ( https://clang.llvm.org/docs/CommandGuide/clang.html and https://reviews.llvm.org/D65880)
*)
let set_3p_prefix_entries cache_keys =
  let rec helper = function
    | [] -> R.ok ()
    | dir :: rst ->
        let null_possible_dir =
          R.ignore_error ~use:(fun _e -> OS.File.null) (Fpath.of_string dir)
        in
        if Fpath.compare OS.File.null null_possible_dir = 0 then
          (* skip over user-submitted directory because it has some parse error *)
          helper rst
        else
          let threep = null_possible_dir in
          (* 1. Remove 3p entries, if any, from compiler variables and PKG_CONFIG_PATH.
              The gcc compiler variables COMPILER_PATH and LIBRARY_PATH are always colon-separated
              per https://gcc.gnu.org/onlinedocs/gcc/Environment-Variables.html#Environment-Variables.
              This _might_ conflict with clang if clang were run on Windows (very very unlikely)
              because clang's CPATH is explicitly OS path separated; perhaps clang's LIBRARY_PATH is as
              well.
          *)
          let f entry =
            let fp = Fpath.of_string entry in
            if R.is_error fp then false
            else not Fpath.(is_prefix threep (R.get_ok fp))
          in
          prune_entries f >>= fun () ->
          (* 2. Add DKML_3P_PREFIX_PATH directories to front of INCLUDE,LIB,...,PKG_CONFIG_PATH and PATH *)
          Logs.debug (fun l ->
              l "third-party prefix directory = %a" Fpath.pp threep);
          prepend_entries ~tools:false threep >>= fun () -> helper rst
  in
  let dirs =
    String.cuts ~empty:false ~sep:";"
      (OS.Env.opt_var ~absent:"" "DKML_3P_PREFIX_PATH")
  in
  Logs.debug (fun l -> l "DKML_3P_PREFIX_PATH = @[%a@]" Fmt.(list string) dirs);
  helper (List.rev dirs) >>| fun () -> String.concat ~sep:";" dirs :: cache_keys

(* [set_3p_program_entries cache_keys] will modify the PATH so that each directory in
   the semicolon separated environment variable DKML_3P_PROGRAM_PATH is present the PATH.
*)
let set_3p_program_entries cache_keys =
  Lazy.force probe_os_path_sep >>= fun os_path_sep ->
  let rec helper = function
    | [] -> R.ok ()
    | dir :: rst ->
        let null_possible_dir =
          R.ignore_error ~use:(fun _e -> OS.File.null) (Fpath.of_string dir)
        in
        if Fpath.compare OS.File.null null_possible_dir = 0 then
          (* skip over user-submitted directory because it has some parse error *)
          helper rst
        else
          let threep = null_possible_dir in
          let f entry =
            let fp = Fpath.of_string entry in
            if R.is_error fp then false
            else not Fpath.(equal threep (R.get_ok fp))
          in
          prune_envvar ~f ~path_sep:os_path_sep "PATH" >>= fun () ->
          Logs.debug (fun l ->
              l "third-party program directory = %a" Fpath.pp threep);
          OS.Env.parse "PATH" OS.Env.(some string) ~absent:None
          >>= prepend_envvar ~path_sep:os_path_sep "PATH"
                (Fpath.to_string threep)
          >>= fun () -> helper rst
  in
  let dirs =
    String.cuts ~empty:false ~sep:";"
      (OS.Env.opt_var ~absent:"" "DKML_3P_PROGRAM_PATH")
  in
  Logs.debug (fun l -> l "DKML_3P_PROGRAM_PATH = @[%a@]" Fmt.(list string) dirs);
  helper (List.rev dirs) >>| fun () -> String.concat ~sep:";" dirs :: cache_keys

let main_with_result () =
  let ( let* ) = R.( >>= ) in

  (* ZEROTH, check and set a recursion guard so that only one set
     of environment mutations is performed.

     The following env mutations will still happen:
     1. [create_and_setenv_if_necessary ()] like initializing the DkML system
     2. On Windows, [set_msys2_entries ()] like MSYSTEM
  *)
  let* has_dkml_mutating_ancestor_process =
    mark_dkml_mutating_ancestor_process ()
  in

  (* Setup logging *)
  Fmt_tty.setup_std_outputs ();
  Logs.set_reporter (Logs_fmt.reporter ());
  (if has_dkml_mutating_ancestor_process then
     (* Incredibly important that we do not print unexpected output.
        For example, [opam install ocaml-system] -> [ocamlc -vnum]
        the [ocamlc -vnum] must print 4.14.0 (or whatever the version is).
        It must not print any logs, even to standard error. *)
     Logs.set_level (Some Logs.Error)
   else
     let dbt = OS.Env.value "DKML_BUILD_TRACE" OS.Env.string ~absent:"OFF" in
     if
       dbt = "ON"
       && OS.Env.value "DKML_BUILD_TRACE_LEVEL" int_parser ~absent:0 >= 2
     then Logs.set_level (Some Logs.Debug)
     else if dbt = "ON" then Logs.set_level (Some Logs.Info)
     else Logs.set_level (Some Logs.Warning));

  let* dkmlversion = Lazy.force get_dkmlversion_or_default in
  let* dkmlmode = Lazy.force get_dkmlmode_or_default in
  let* target_abi =
    Rresult.R.error_to_msg ~pp_error:Fmt.string
      (Dkml_c_probe.C_abi.V2.get_abi_name ())
  in
  let cache_keys = [ dkmlversion ] in
  (* FIRST, set DKML_TARGET_ABI, which may be overridden by DKML_TARGET_PLATFORM_OVERRIDE *)
  let target_abi =
    OS.Env.opt_var "DKML_TARGET_PLATFORM_OVERRIDE" ~absent:target_abi
  in
  let* () =
    if has_dkml_mutating_ancestor_process then Ok ()
    else OS.Env.set_var "DKML_TARGET_ABI" (Some target_abi)
  in
  let cache_keys = target_abi :: cache_keys in
  (* SECOND, set MSYS2 environment variables.
     - This is needed before is_msys2_msys_build_machine() is called from crossplatform-functions.sh
       in add_microsoft_visual_studio_entries.
     - This also needs to happen before add_microsoft_visual_studio_entries so that MSVC `link.exe`
       can be inserted by VsDevCmd.bat before any MSYS2 `link.exe`. (`link.exe` is one example of many
       possible conflicts).
  *)
  let* () =
    match dkmlmode with
    | Nativecode ->
        set_msys2_entries ~has_dkml_mutating_ancestor_process ~target_abi
    | Bytecode -> Ok ()
  in
  let* () =
    if has_dkml_mutating_ancestor_process then Ok ()
    else
      (* THIRD, set temporary variables *)
      set_tempvar_entries cache_keys >>= fun cache_keys ->
      (* FOURTH, set MSVC entries.
         Since MSVC requires temporary variables, we do this after temp vars *)
      (match dkmlmode with
      | Nativecode -> set_msvc_entries cache_keys
      | Bytecode -> Ok cache_keys)
      >>= fun cache_keys ->
      (* FIFTH, set third-party (3p) prefix entries.
         Since MSVC overwrites INCLUDE and LIB entirely, we have to do
         third party entries (like vcpkg) _after_ MSVC. *)
      set_3p_prefix_entries cache_keys >>= fun cache_keys ->
      (* SIXTH, set third-party (3p) program entries. *)
      set_3p_program_entries cache_keys >>= fun _cache_keys -> Ok ()
  in
  (* SEVENTH, Create a command line like `...\usr\bin\env.exe CMD [ARGS...]`.
     More environment entries can be made, but this is at the end where
     there is no need to cache the environment. *)
  let* cmd =
    Cmdline.create_and_setenv_if_necessary ~has_dkml_mutating_ancestor_process
      ()
  in
  let* () =
    if has_dkml_mutating_ancestor_process then Ok ()
    else
      (* EIGHTH, stop tracing variables from propagating. *)
      let* () = OS.Env.set_var "DKML_BUILD_TRACE" None in
      OS.Env.set_var "DKML_BUILD_TRACE_LEVEL" None
  in
  (* Diagnostics *)
  let* current_env = OS.Env.current () in
  let* current_dir = OS.Dir.current () in
  Logs.debug (fun l ->
      l "Environment:@\n%a" Astring.String.Map.dump_string_map current_env);
  Logs.debug (fun l -> l "Current directory: %a" Fpath.pp current_dir);
  let* () =
    Lazy.force get_dkmlhome_dir_opt >>| function
    | None -> ()
    | Some dkmlhome_dir ->
        Logs.debug (fun l -> l "DkML home directory: %a" Fpath.pp dkmlhome_dir)
  in
  Logs.info (fun l -> l "Running command: %a" Cmd.pp cmd);

  (* Run the command *)
  OS.Cmd.run_status cmd >>| function
  | `Exited status -> exit status
  | `Signaled signal ->
      (* https://stackoverflow.com/questions/1101957/are-there-any-standard-exit-status-codes-in-linux/1535733#1535733 *)
      exit (128 + signal)

let () =
  match main_with_result () with
  | Ok _ -> ()
  | Error msg ->
      Fmt.pf Fmt.stderr "FATAL: %a@\n" Rresult.R.pp_msg msg;
      exit 1
