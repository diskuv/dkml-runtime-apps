open Bos
open Rresult

let fpath_notnull f = Fpath.compare OS.File.null f <> 0

(** [get_opam_root] is a lazy function that gets the OPAMROOT environment variable.
    If OPAMROOT is not found, then <LOCALAPPDATA>/opam is used for Windows
    and $XDG_CONFIG_HOME/opam with fallback to ~/.config/opam for Unix instead.

    Conforms to https://github.com/ocaml/opam/pull/4815#issuecomment-910137754.
  *)
let get_opam_root =
  lazy
    ( OS.Env.parse "LOCALAPPDATA" OS.Env.path ~absent:OS.File.null
    >>= fun localappdata ->
      OS.Env.parse "XDG_CONFIG_HOME" OS.Env.path ~absent:OS.File.null
      >>= fun xdgconfighome ->
      OS.Env.parse "HOME" OS.Env.path ~absent:OS.File.null >>= fun home ->
      OS.Env.parse "OPAMROOT" OS.Env.path ~absent:OS.File.null
      >>= fun opamroot ->
      match
        ( fpath_notnull opamroot,
          fpath_notnull localappdata,
          fpath_notnull xdgconfighome,
          fpath_notnull home )
      with
      | true, _, _, _ -> R.ok opamroot
      | false, true, _, _ -> R.ok Fpath.(localappdata / "opam")
      | false, false, true, _ -> R.ok Fpath.(xdgconfighome / "opam")
      | false, false, false, true -> R.ok Fpath.(home / ".config" / "opam")
      | false, false, false, false ->
          R.error_msg
            "Unable to locate Opam root because none of LOCALAPPDATA, \
             XDG_CONFIG_HOME, HOME or OPAMROOT was set" )

let get_opam_switch_prefix =
  lazy
    ( Lazy.force get_opam_root >>= fun opamroot ->
      OS.Env.parse "OPAM_SWITCH_PREFIX" OS.Env.path ~absent:OS.File.null
      >>| fun opamswitchprefix ->
      if fpath_notnull opamswitchprefix then opamswitchprefix
      else Fpath.(opamroot / "playground") )

(** [SystemConfig] is the state of a DkML system after initial installation, and possibly after.
    
    Initial installation does not include the system OCaml compiler, but it may be installed
    after.
    
    MSYS2 is always part of the initial installation on Windows, but is not present on
    Unix. *)
module SystemConfig = struct
  type msys2_t = Msys2_on_windows of Fpath.t | No_msys2_on_unix

  type t = {
    scripts_dir_fp : Fpath.t;
    env_exe_wrapper : string list;
    target_abi : string;
    msys2 : msys2_t;
    opam_home_fp : Fpath.t;
    ocaml_compiler_version : string;
    ocaml_home_fp_opt : Fpath.t option;
  }

  (** [find_ocaml_home] finds the DkML home directory if it contains usr/bin/ocamlc *)
  let find_ocaml_home () =
    let ( let* ) = Result.bind in
    let* dkml_home_fp = Lazy.force Dkml_context.get_dkmlhome_dir_or_default in
    let* ocaml_fp_opt =
      OS.Cmd.find_tool
        ~search:Fpath.[ dkml_home_fp / "usr" / "bin" ]
        (Cmd.v "ocamlc")
    in
    match ocaml_fp_opt with
    | None -> Ok None
    | Some ocaml_fp ->
        let ocaml_bin1_fp, _ = Fpath.split_base ocaml_fp in
        let* () =
          if "bin" = Fpath.basename ocaml_bin1_fp then Ok ()
          else
            Rresult.R.error_msgf "Expected %a to be in a bin/ directory"
              Fpath.pp ocaml_fp
        in
        let ocaml_bin2_fp, _ = Fpath.split_base ocaml_bin1_fp in
        let ocaml_bin3_fp, _ = Fpath.split_base ocaml_bin2_fp in
        let ocaml_home_fp =
          if "usr" = Fpath.basename ocaml_bin2_fp then ocaml_bin3_fp
          else ocaml_bin2_fp
        in
        Ok (Some ocaml_home_fp)

  let create ~scripts_dir_fp () =
    let ( let* ) = Result.bind in
    (* Read OCaml compiler version *)
    let* ocaml_compiler_version =
      (* let* () =
           OS.Cmd.run
             Cmd.(v "with-dkml" % "find" % Fpath.(to_string scripts_dir_fp))
         in *)
      OS.File.read
        Fpath.(
          scripts_dir_fp / "vendor" / "dkml-compiler" / "src"
          / "version.ocaml.txt")
    in
    let ocaml_compiler_version = String.trim ocaml_compiler_version in
    (* Find env *)
    let* env_exe_wrapper = Dkml_environment.env_exe_wrapper () in
    (* Find target ABI *)
    let* target_abi =
      Rresult.R.error_to_msg ~pp_error:Fmt.string
        (Dkml_c_probe.C_abi.V2.get_abi_name ())
    in
    (* Find optional MSYS2 *)
    let* msys2 =
      if Sys.win32 then
        let* msys2_dir = Lazy.force Dkml_context.get_msys2_dir in
        Ok (Msys2_on_windows msys2_dir)
      else Ok No_msys2_on_unix
    in
    (* Figure out OPAMHOME which is the DkML home directory as long as it contains the bin/opam *)
    let* dkml_home_fp = Lazy.force Dkml_context.get_dkmlhome_dir_or_default in
    let* opam_fp =
      OS.Cmd.get_tool ~search:Fpath.[ dkml_home_fp / "bin" ] (Cmd.v "opam")
    in
    let opam_bin1_fp, _ = Fpath.split_base opam_fp in
    let* () =
      if "bin" = Fpath.basename opam_bin1_fp then Ok ()
      else
        Rresult.R.error_msgf "Expected %a to be in a bin/ directory" Fpath.pp
          opam_fp
    in
    let opam_home_fp, _ = Fpath.split_base opam_bin1_fp in
    (* Figure out OCAMLHOME containing usr/bin/ocamlc or bin/ocamlc *)
    let* ocaml_home_fp_opt = find_ocaml_home () in
    Ok
      {
        scripts_dir_fp;
        env_exe_wrapper;
        target_abi;
        msys2;
        opam_home_fp;
        ocaml_compiler_version;
        ocaml_home_fp_opt;
      }
end

let get_msys2_create_opam_switch_options = function
  | SystemConfig.No_msys2_on_unix -> []
  | SystemConfig.Msys2_on_windows msys2_dir ->
      (*
       MSYS2 sets PKG_CONFIG_SYSTEM_{INCLUDE,LIBRARY}_PATH which causes
       native Windows pkgconf to not see MSYS2 packages.

       Confer:
       https://github.com/pkgconf/pkgconf#compatibility-with-pkg-config
       https://github.com/msys2/MSYS2-packages/blob/f953d15d0ede1dfb8656a8b3e27c2b694fa1e9a7/filesystem/profile#L54-L55

       Replicated (and need to change if these change):
       [dkml/packaging/version-bump/upsert-dkml-switch.in.sh]
       [dkml-component-ocamlcompiler/assets/staging-files/win32/setup-userprofile.ps1]
    *)
      [
        "-e";
        Fmt.str "PKG_CONFIG_PATH=%a" Fpath.pp
          Fpath.(msys2_dir / "clang64" / "lib" / "pkgconfig");
        "-e";
        "PKG_CONFIG_SYSTEM_INCLUDE_PATH=";
        "-e";
        "PKG_CONFIG_SYSTEM_LIBRARY_PATH=";
      ]
