open Rresult
open Dkml_context
open Bos
open Astring

let guard_envname = "DKML_GUARD"

(** Marks this process as a DkML environment mutating process if there is no
    such process as an ancestor. 

    DkML environment mutations are:
    - setting DkML compiler environment variables like INCLUDE and LIB for MSVC
    - initializing the DkML system (OCaml compiler, opam root, etc.)

    Returns true if and only if an ancestor (either ["dkml.exe"] or ["with-dkml.exe"])
    had been marked as DkML environment mutating. *)
let mark_dkml_mutating_ancestor_process () =
  let guard_value = OS.Env.opt_var guard_envname ~absent:"0" in
  let pid_str = Int.to_string (Unix.getpid ()) in
  let has_ancestor =
    (not (String.equal guard_value "0"))
    && not (String.equal guard_value pid_str)
  in
  if has_ancestor then Ok true
  else
    let ( let* ) = Result.bind in
    let* () = OS.Env.set_var guard_envname (Some pid_str) in
    Ok false

let platform_path_norm s =
  match Dkml_c_probe.C_abi.V2.get_os () with
  | Ok IOS | Ok OSX | Ok Windows -> String.Ascii.lowercase s
  | Ok Android | Ok Linux -> s
  | Error msg ->
      Fmt.pf Fmt.stderr "FATAL: %s@\n" msg;
      exit 1

let path_contains entry s =
  String.find_sub ~sub:(platform_path_norm s) (platform_path_norm entry)
  |> Option.is_some

let path_starts_with entry s =
  String.is_prefix ~affix:(platform_path_norm s) (platform_path_norm entry)

let path_ends_with entry s =
  String.is_suffix ~affix:(platform_path_norm s) (platform_path_norm entry)

(** [prune_path_of_msys2 ()] removes .../MSYS2/usr/bin from the PATH environment variable *)
let prune_path_of_msys2 prefix =
  OS.Env.req_var "PATH" >>= fun path ->
  String.cuts ~empty:false ~sep:";" path
  |> List.filter (fun entry ->
         let ends_with = path_ends_with entry in
         (not (ends_with "\\MSYS2\\usr\\bin"))
         && not (ends_with ("\\MSYS2\\" ^ prefix ^ "\\bin")))
  |> fun paths -> Some (String.concat ~sep:";" paths) |> OS.Env.set_var "PATH"

type msys2_config = {
  opam_host_arch : string;
      (** The ["host-arch-*"] opam package. Example: {{:https://v3.ocaml.org/p/host-arch-x86_64/latest}https://v3.ocaml.org/p/host-arch-x86_64/latest}*)
  msystem : string;
  msystem_carch : string;
  msystem_chost : string;
  msystem_prefix : string;
  mingw_chost : string;
  mingw_prefix : string;
  mingw_package_prefix : string;
}

(** [get_msys2_environment target_abi] gets the DkML environment for the DkML
    ABI [target_abi].
    
    See {{:https://github.com/msys2/MSYS2-packages/blob/1ff9c79a6b6b71492c4824f9888a15314b85f5fa/filesystem/msystem}MSYS2-packages/filesystem/msystem}
    and {{:https://www.msys2.org/docs/environments/}MSYS2 Environments} for the magic values.

    + MSYSTEM = MINGW32 or CLANG64
    + MSYSTEM_CARCH, MSYSTEM_CHOST, MSYSTEM_PREFIX
    + MINGW_CHOST, MINGW_PREFIX, MINGW_PACKAGE_PREFIX

    {3 32 bit notes}

    There is no 32-bit MSYS2 tooling (well, 32-bit was deprecated), but you don't need 32-bit
    MSYS2 binaries; just a 32-bit (cross-)compiler.

    We should use CLANG32, but it is still experimental as of 2022-05-11.
    So we use MINGW32.

    Confer: {{:https://issuemode.com/issues/msys2/MINGW-packages/18837088}https://issuemode.com/issues/msys2/MINGW-packages/18837088}
*)
let get_msys2_environment ~target_abi =
  let cfg c0 c1 c2 c3 c4 c5 c6 c7 =
    Ok
      {
        opam_host_arch = c0;
        msystem = c1;
        msystem_carch = c2;
        msystem_chost = c3;
        msystem_prefix = c4;
        mingw_chost = c5;
        mingw_prefix = c6;
        mingw_package_prefix = c7;
      }
  in
  (* Replicated (and need to change if these change):
     [dkml-runtime-apps/src/runtimelib/dkml_environment.ml]
     [dkml/packaging/version-bump/upsert-dkml-switch.in.sh]
  *)
  match target_abi with
  | "windows_x86" ->
      cfg "host-arch-x86_32" "MINGW32" "i686" "i686-w64-mingw32" "mingw32"
        "i686-w64-mingw32" "mingw32" "mingw-w64-i686"
  | "windows_x86_64" ->
      cfg "host-arch-x86_64" "CLANG64" "x86_64" "x86_64-w64-mingw32" "clang64"
        "x86_64-w64-mingw32" "clang64" "mingw-w64-clang-x86_64"
  | "windows_arm64" ->
      cfg "host-arch-arm64" "CLANGARM64" "aarch64" "aarch64-w64-mingw32"
        "clangarm64" "aarch64-w64-mingw32" "clangarm64"
        "mingw-w64-clang-aarch64"
  | _ ->
      Error
        (`Msg
          ("The target platform name '" ^ target_abi
         ^ "' is not a supported Windows platform"))

(** Set the MSYSTEM environment variable to MSYS and place MSYS2 binaries at the front of the PATH.
    Any existing MSYS2 binaries in the PATH will be removed.
  *)
let set_msys2_entries ~has_dkml_mutating_ancestor_process ~target_abi =
  Lazy.force get_msys2_dir_opt >>= function
  | None -> R.ok ()
  | Some msys2_dir ->
      (* See https://github.com/msys2/MSYS2-packages/blob/1ff9c79a6b6b71492c4824f9888a15314b85f5fa/filesystem/msystem and
         https://www.msys2.org/docs/environments/ for the magic values.

          1. MSYSTEM = MINGW32 or CLANG64
          2. MSYSTEM_CARCH, MSYSTEM_CHOST, MSYSTEM_PREFIX
          3. MINGW_CHOST, MINGW_PREFIX, MINGW_PACKAGE_PREFIX

          32 bit notes
          ------------

          There is no 32-bit MSYS2 tooling (well, 32-bit was deprecated), but you don't need 32-bit
          MSYS2 binaries; just a 32-bit (cross-)compiler.

          We should use CLANG32, but it is still experimental as of 2022-05-11.
          So we use MINGW32.
          Confer: https://issuemode.com/issues/msys2/MINGW-packages/18837088
      *)
      get_msys2_environment ~target_abi
      >>= fun {
                opam_host_arch = _;
                msystem;
                msystem_carch;
                msystem_chost;
                msystem_prefix;
                mingw_chost;
                mingw_prefix;
                mingw_package_prefix;
              } ->
      OS.Env.set_var "MSYSTEM" (Some msystem) >>= fun () ->
      OS.Env.set_var "MSYSTEM_CARCH" (Some msystem_carch) >>= fun () ->
      OS.Env.set_var "MSYSTEM_CHOST" (Some msystem_chost) >>= fun () ->
      OS.Env.set_var "MSYSTEM_PREFIX" (Some ("/" ^ msystem_prefix))
      >>= fun () ->
      OS.Env.set_var "MINGW_CHOST" (Some mingw_chost) >>= fun () ->
      OS.Env.set_var "MINGW_PREFIX" (Some ("/" ^ mingw_prefix)) >>= fun () ->
      OS.Env.set_var "MINGW_PACKAGE_PREFIX" (Some mingw_package_prefix)
      >>= fun () ->
      (* 2. Fix the MSYS2 ambiguity problem described at https://github.com/msys2/MSYS2-packages/issues/2316.
         Our error is running:
           cl -nologo -O2 -Gy- -MD -Feocamlrun.exe prims.obj libcamlrun.lib advapi32.lib ws2_32.lib version.lib /link /subsystem:console /ENTRY:wmainCRTStartup
         would warn
           cl : Command line warning D9002 : ignoring unknown option '/subsystem:console'
           cl : Command line warning D9002 : ignoring unknown option '/ENTRY:wmainCRTStartup'
         because the slashes (/) could mean Windows paths or Windows options. We force the latter.

         This is described in Automatic Unix ⟶ Windows Path Conversion
         at https://www.msys2.org/docs/filesystem-paths/
      *)
      OS.Env.set_var "MSYS2_ARG_CONV_EXCL" (Some "*") >>= fun () ->
      (* 3. Remove MSYS2 entries, if any, from PATH
            _unless_ we are minimizing side-effects *)
      (if has_dkml_mutating_ancestor_process then Ok ()
       else prune_path_of_msys2 msystem_prefix)
      >>= fun () ->
      (* 4. Add MSYS2 <prefix>/bin and /usr/bin to front of PATH
            _unless_ we are minimizing side-effects. *)
      if has_dkml_mutating_ancestor_process then Ok ()
      else
        OS.Env.req_var "PATH" >>= fun path ->
        OS.Env.set_var "PATH"
          (Some
             (Fpath.(msys2_dir / msystem_prefix / "bin" |> to_string)
             ^ ";"
             ^ Fpath.(msys2_dir / "usr" / "bin" |> to_string)
             ^ ";" ^ path))

(** Get a wrapper like /usr/bin/env or equivalent or nothing *)
let env_exe_wrapper () =
  let ( let* ) = Rresult.R.( >>= ) in
  let* slash = Fpath.of_string "/" in
  let* x = Lazy.force Dkml_context.get_msys2_dir_opt in
  match (x, Sys.win32) with
  | None, true ->
      (* On Windows w/o MSYS2 (like Bytecode Edition) there will be no env. *)
      Ok []
  | None, false ->
      (* /usr/bin/env should always exist on Unix. *)
      Ok [ Fpath.(slash / "usr" / "bin" / "env" |> to_string) ]
  | Some msys2_dir, _ ->
      Logs.debug (fun m -> m "MSYS2 directory: %a" Fpath.pp msys2_dir);
      Ok [ Fpath.(msys2_dir / "usr" / "bin" / "env.exe" |> to_string) ]
