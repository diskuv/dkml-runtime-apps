open Rresult
open Dkml_context
open Bos
open Astring

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

(** Set the MSYSTEM environment variable to MSYS and place MSYS2 binaries at the front of the PATH.
    Any existing MSYS2 binaries in the PATH will be removed.
  *)
let set_msys2_entries ~minimize_sideeffects target_platform_name =
  Lazy.force get_msys2_dir_opt >>= function
  | None -> R.ok ()
  | Some msys2_dir ->
      (* See https://www.msys2.org/docs/environments/ for the magic values.

          1. MSYSTEM = MINGW32 or CLANG64
          2. MSYSTEM_CARCH, MSYSTEM_CHOST, MSYSTEM_PREFIX for 64-bit MSYS

          There is no 32-bit MSYS2 tooling (well, 32-bit was deprecated), but you don't need 32-bit
          MSYS2 binaries; just a 32-bit (cross-)compiler.

          We should use CLANG32, but it is still experimental as of 2022-05-11.
          So we use MINGW32.
          Confer: https://issuemode.com/issues/msys2/MINGW-packages/18837088
      *)
      (match target_platform_name with
      | "windows_x86" -> R.ok ("MINGW32", "i686", "i686-w64-mingw32", "mingw32")
      | "windows_x86_64" ->
          R.ok ("CLANG64", "x86_64", "x86_64-w64-mingw32", "clang64")
      | "windows_arm64" ->
          R.ok ("CLANGARM64", "aarch64", "aarch64-w64-mingw32", "clangarm64")
      | _ ->
          R.error_msg @@ "The target platform name '" ^ target_platform_name
          ^ "' is not a supported Windows platform")
      >>= fun (msystem, carch, chost, prefix) ->
      OS.Env.set_var "MSYSTEM" (Some msystem) >>= fun () ->
      OS.Env.set_var "MSYSTEM_CARCH" (Some carch) >>= fun () ->
      OS.Env.set_var "MSYSTEM_CHOST" (Some chost) >>= fun () ->
      OS.Env.set_var "MSYSTEM_PREFIX" (Some ("/" ^ prefix)) >>= fun () ->
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
      (if minimize_sideeffects then Ok () else prune_path_of_msys2 prefix)
      >>= fun () ->
      (* 4. Add MSYS2 <prefix>/bin and /usr/bin to front of PATH
            _unless_ we are minimizing side-effects. *)
      if minimize_sideeffects then Ok ()
      else
        OS.Env.req_var "PATH" >>= fun path ->
        OS.Env.set_var "PATH"
          (Some
             (Fpath.(msys2_dir / prefix / "bin" |> to_string)
             ^ ";"
             ^ Fpath.(msys2_dir / "usr" / "bin" |> to_string)
             ^ ";" ^ path))
