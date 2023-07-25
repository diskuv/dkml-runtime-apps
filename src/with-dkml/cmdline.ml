open Bos
open Astring

(** On Windows ["winget install opam"] will install a version of opam that
    is compiled without any patches; in fact any installation of
    dkml-component-offline-opam will do the same. That means we need with-dkml
    to set up the PATH so that opam can find for example ["cp"] (which is not
    available on Windows unless you add MSYS2 or Cygwin to the PATH).

    So any with-dkml shim of opam should delegate to the winget installed
    opam after the shim sets up the PATH (and all the other things it does). *)
let find_authoritative_opam_exe =
  lazy
    (match OS.Env.var "LOCALAPPDATA" with
    | Some localappdata when not (String.equal localappdata "") ->
        Some Fpath.(v localappdata / "Programs" / "opam" / "bin" / "opam")
    | _ -> (
        match OS.Env.var "HOME" with
        | Some home when not (String.equal home "") ->
            Some Fpath.(v home / ".local" / "bin" / "opam")
        | _ -> None))

let is_basename_of_filename_in_search_list ~search_list_lowercase filename =
  match Fpath.of_string filename with
  | Ok argv0_p ->
      let n = String.Ascii.lowercase @@ Fpath.filename argv0_p in
      List.mem n search_list_lowercase
  | Error _ -> false

let is_with_dkml_exe filename =
  let search_list_lowercase =
    [
      "with_dkml";
      "with_dkml.exe";
      "with-dkml";
      "with-dkml.exe";
      (* DOS 8.3: WITH-D~1.EXE *)
      "with-d~1";
      "with-d~1.exe";
    ]
  in
  is_basename_of_filename_in_search_list ~search_list_lowercase filename

(** [is_bytecode_exe path] is true if and only if the [path] has a basename
    known to run or need bytecode (down, dune, ocaml, ocamlc, ocamlfind, utop,
    utop-full) and also is inside a ["bin/"] directory.
    
    [dune] and [ocamlfind] are special because they depend on the value of
    DiskuvOCamlMode=native|byte. It can either produce native code (which means
    it needs an end-user compiled ocamlopt.exe, or a not-yet-completed
    relocatable ocamlopt compiler) or it can produce byte code (which means
    it needs a stdlib and third party libraries that share the same ocamlobjinfo
    checksums ... no "Inconsistent assumptions over interface"). Said another
    way, the native code (end-user compiled binaries and stdlib) are
    incompatible with the pre-built bytecode (stdlib and 3rd party libraries).
    *)
let is_bytecode_exe path =
  let ( let* ) = Rresult.R.( >>= ) in
  let* mode = Lazy.force Dkml_runtimelib.get_dkmlmode in
  let execs = [ "down"; "ocaml"; "ocamlc"; "utop"; "utop-full" ] in
  let execs =
    match mode with
    | Nativecode -> execs
    | Bytecode -> "ocamlfind" :: "dune" :: execs
  in
  let search_list_lowercase =
    List.map (fun filename -> [ filename; filename ^ ".exe" ]) execs
    |> List.flatten
  in
  let n = Fpath.filename path in
  match List.mem n search_list_lowercase with
  | false -> Ok false
  | true -> Ok (String.equal "bin" Fpath.(basename (parent path)))

let is_opam_exe filename =
  let search_list_lowercase = [ "opam"; "opam.exe" ] in
  is_basename_of_filename_in_search_list ~search_list_lowercase filename

let is_blurb_exe filename =
  (* Any command line interpreters *)
  let search_list_lowercase =
    [
      "down";
      "down.exe";
      "ocaml";
      "ocaml.exe";
      "utop";
      "utop.exe";
      "utop-full";
      "utop-full.exe";
    ]
  in
  is_basename_of_filename_in_search_list ~search_list_lowercase filename

let canonical_path_sep = if Sys.win32 then ";" else ":"

let when_dir_exists_prepend_pathlike_env ~envvar dir =
  let ( let* ) = Rresult.R.( >>= ) in
  let old_path, existing_paths =
    match OS.Env.var envvar with
    | None -> ("", [])
    | Some path -> (path, String.cuts ~empty:false ~sep:canonical_path_sep path)
  in
  let* dir_exists = OS.Dir.exists dir in
  if dir_exists then
    let entry = Fpath.to_string dir in
    if List.mem entry existing_paths then (
      Logs.debug (fun l ->
          l "Skipping adding pre-existent %a to PATH" Fpath.pp dir);
      Ok ())
    else (
      Logs.debug (fun l -> l "Prepending %a to %s" Fpath.pp dir envvar);
      let new_path =
        if String.equal "" old_path then entry
        else entry ^ canonical_path_sep ^ old_path
      in
      OS.Env.set_var envvar (Some new_path))
  else Ok ()

let when_path_exists_set_env ~envvar path =
  let ( let* ) = Rresult.R.( >>= ) in
  let* path_exists = OS.Path.exists path in
  if path_exists then (
    let entry = Fpath.to_string path in
    Logs.debug (fun l -> l "Setting %s to %a" envvar Fpath.pp path);
    OS.Env.set_var envvar (Some entry))
  else Ok ()

let set_precompiled_env abs_cmd_p =
  let ( let* ) = Rresult.R.( >>= ) in
  (* In Opam switch or in global environment?

      Do not use the global bytecode environment if inside an Opam switch.
      Really only applies to [dune] which has a dune+shim package.
  *)
  match OS.Env.opt_var ~absent:"" "OPAM_SWITCH_PREFIX" with
  | "" ->
      (* Not in an Opam switch. *)
      (* Installation prefix *)
      let prefix_p = Fpath.(parent (parent abs_cmd_p)) in
      let bc_p = Fpath.(prefix_p / "desktop" / "bc") in
      let bc_bin_p = Fpath.(bc_p / "bin") in
      let bc_ocaml_lib_p = Fpath.(bc_p / "lib" / "ocaml") in
      let bc_ocaml_stublibs_p = Fpath.(bc_ocaml_lib_p / "stublibs") in
      let bc_stublibs_p = Fpath.(bc_p / "lib" / "stublibs") in
      let findlib_conf =
        Fpath.(prefix_p / "usr" / "lib" / "findlib-precompiled.conf")
      in
      (* OCAMLLIB *)
      let* () = when_path_exists_set_env ~envvar:"OCAMLLIB" bc_ocaml_lib_p in
      (* OCAMLFIND_CONF *)
      let* () =
        when_path_exists_set_env ~envvar:"OCAMLFIND_CONF" findlib_conf
      in
      let* () =
        match Sys.win32 with
        | true ->
            (* Windows requires DLLs in PATH *)
            let* () =
              when_dir_exists_prepend_pathlike_env ~envvar:"PATH"
                bc_ocaml_stublibs_p
            in
            when_dir_exists_prepend_pathlike_env ~envvar:"PATH" bc_stublibs_p
        | false ->
            (* Unix (generally) requires .so in LD_LIBRARY_PATH *)
            let* () =
              when_dir_exists_prepend_pathlike_env ~envvar:"LD_LIBRARY_PATH"
                bc_ocaml_stublibs_p
            in
            when_dir_exists_prepend_pathlike_env ~envvar:"LD_LIBRARY_PATH"
              bc_stublibs_p
      in
      (* Dune requires ocamlc in the PATH. It should already be present
         but just in case put the bytecode executables in the PATH *)
      let* () = when_dir_exists_prepend_pathlike_env ~envvar:"PATH" bc_bin_p in
      Ok ()
  | _ ->
      (* In an Opam switch

         TODO: For [utop] especially it would be good to set the bytecode
         environment to the Opam switch and long as the opam switch does
         not have its own stdlib from an ocaml compiler. *)
      Ok ()

let set_enduser_env abs_cmd_p =
  match OS.Env.opt_var ~absent:"" "OPAM_SWITCH_PREFIX" with
  | "" ->
      (* Not in an Opam switch. *)
      (* Installation prefix *)
      let prefix_p = Fpath.(parent (parent abs_cmd_p)) in
      let findlib_conf =
        Fpath.(prefix_p / "usr" / "lib" / "findlib-enduser.conf")
      in
      (* OCAMLFIND_CONF. Only necessary because no ocamlfind package (or
         any other package) is present after the OCaml compiler is installed. *)
      when_path_exists_set_env ~envvar:"OCAMLFIND_CONF" findlib_conf
  | _ -> Ok ()

let blurb () =
  let ( let* ) = Rresult.R.( >>= ) in
  let* version = Lazy.force Dkml_runtimelib.get_dkmlversion in
  Format.eprintf
    {|DkML %-49s https://diskuv.com/dkmlbook/
DkSDK%-49s https://diskuv.com/cmake/help/latest/
@.|}
    (version ^ ": Open source. Full-stack OCaml.")
    ": 30 day risk free. C/C++/Java/Swift and OCaml.";
  Ok ()

(** Create a command line like [let cmdline_a = [".../usr/bin/env.exe"; Args.others]]
    or [let cmdline_b = ["XYZ-real.exe"; Args.others]]
    or [let cmdline_c = [".../usr/bin/env.exe"; "XYZ-real.exe"; Args.others]].

    We use env.exe because it has logic to check if CMD is a shell
    script and run it accordingly (MSYS2 always uses bash for some reason, instead
    of looking at shebang). And it seems to setup the environment
    so things like the pager (ex. ["opam --help"]) work correctly.

    If the current executable is named ["with-dkml"] or ["with_dkml"], then
    the [cmdline_a] form of the command line is run.

    If the current executable is named ["opam"] and the arguments are of form:
    * [["env"; ...]]
    * [["switch"]]
    * [["switch"; "--some-option"; ...]]
    * [["switch"; "list"; ...]]
    then the [cmdline_b] form of the command line is run.
    Opam will probe the parent process ({!OpamSys.windows_get_shell})
    to discover if the user needs PowerShell, Unix or Command Prompt syntax;
    by not inserting [".../usr/bin/env.exe"] we don't fool Opam into thinking
    we want Unix syntax.

    Otherwise the [cmdline_c] command line is chosen, where the current
    executable is named ["XYZ.exe"]. If you distribute binaries all you
    need to do is rename ["dune.exe"] to ["dune-real.exe"] and
    ["with-dkml.exe"] to ["dune.exe"], and the new ["dune.exe"] will behave
    like the old ["dune.exe"], but will have all the UNIX tools through MSYS
    and the MSVC compiler available to it. You can do the same with
    ["opam.exe"] or any other executable.

    Special case: If the current executable is a bytecode executable (one of
    ["ocaml"; "down"; "utop"; "utop-full"; "utop"]) and the current executable
    is in a ["bin/"] folder, then:
    
    1. ["../usr/lib/findlib.conf"] is set as the OCAMLFIND_CONF if the configuration
    file exists.
    2. ["../lib/ocaml"] is set as the OCAMLLIB (used by <ocaml>/utils/config.ml
       [standard_library]) if the directory exists.
    3. ["../lib/ocaml/stublibs"] and ["../share/bc/lib/stublibs"] are added to
    the PATH on Windows (or LD_LIBRARY_PATH on Unix) if the directories exist.
*)
let create_and_setenv_if_necessary () =
  let ( let* ) = Rresult.R.( >>= ) in
  let ( let+ ) = Rresult.R.( >>| ) in
  let* slash = Fpath.of_string "/" in
  let* env_exe =
    let* x = Lazy.force Dkml_runtimelib.get_msys2_dir_opt in
    match x with
    | None -> Ok Fpath.(slash / "usr" / "bin" / "env")
    | Some msys2_dir ->
        Logs.debug (fun m -> m "MSYS2 directory: %a" Fpath.pp msys2_dir);
        Ok Fpath.(msys2_dir / "usr" / "bin" / "env.exe")
  in
  let get_authoritative_opam_exe () =
    match Lazy.force find_authoritative_opam_exe with
    | Some authoritative_opam_exe ->
        OS.Cmd.find_tool (Cmd.v @@ Fpath.to_string authoritative_opam_exe)
    | None -> Ok None
  in
  let get_real_exe cmd_no_ext_p =
    let dir, b = Fpath.split_base cmd_no_ext_p in
    let real_p = Fpath.(dir / (filename b ^ "-real")) in
    let+ real_exe_p = OS.Cmd.get_tool (Cmd.v (Fpath.to_string real_p)) in
    real_exe_p
  in
  let get_abs_cmd_and_real_exe ?opam cmd =
    Logs.debug (fun l -> l "Desired command is named: %s" cmd);
    (* If the command is not absolute like "dune", then we need to find
       the absolute location of it. *)
    let* abs_cmd_p = OS.Cmd.get_tool (Cmd.v cmd) in
    Logs.debug (fun l -> l "Absolute command path is: %a" Fpath.pp abs_cmd_p);
    (* Edge case: If ~opam:() then look for authoritative opam first *)
    let* authoritative_real_exe_opt =
      if opam = Some () then get_authoritative_opam_exe () else Ok None
    in
    let authoritative_real_exe_opt =
      (* Can only use it if it actually exists *)
      match authoritative_real_exe_opt with
      | Some authoritative_real_exe ->
          Logs.debug (fun l ->
              l "Authoritative command, if any, expected at: %a" Fpath.pp
                authoritative_real_exe);
          if OS.File.is_executable authoritative_real_exe then
            Some authoritative_real_exe
          else None
      | None -> None
    in
    (* General case: The -real command is in the same directory *)
    let* real_exe =
      match authoritative_real_exe_opt with
      | Some authoritative_real_exe ->
          Logs.debug (fun l ->
              l "Using authoritative command: %a" Fpath.pp
                authoritative_real_exe);
          Ok authoritative_real_exe
      | None ->
          let before_ext, ext = Fpath.split_ext abs_cmd_p in
          let cmd_no_ext_p = if ext = ".exe" then before_ext else abs_cmd_p in
          let* real_p = get_real_exe cmd_no_ext_p in
          Logs.debug (fun l ->
              l "Using sibling real command: %a" Fpath.pp real_p);
          Ok real_p
    in
    Ok (abs_cmd_p, real_exe)
  in
  let+ cmd_and_args =
    match Array.to_list Sys.argv with
    (* CMDLINE_A FORM *)
    | cmd :: args when is_with_dkml_exe cmd ->
        Ok ([ Fpath.to_string env_exe ] @ args)
    (* CMDLINE_B FORM *)
    | cmd :: "env" :: args when is_opam_exe cmd ->
        Logs.debug (fun l ->
            l
              "Detected [opam env ...] invocation. Not using 'env opam env' so \
               Opam can discover the parent shell");
        let* _abs_cmd_p, real_exe = get_abs_cmd_and_real_exe ~opam:() cmd in
        Ok ([ Fpath.to_string real_exe; "env" ] @ args)
    | [ cmd; "switch" ] when is_opam_exe cmd ->
        Logs.debug (fun l ->
            l
              "Detected [opam switch] invocation. Not using 'env opam switch' \
               so Opam can discover the parent shell");
        let* _abs_cmd_p, real_exe = get_abs_cmd_and_real_exe ~opam:() cmd in
        Ok [ Fpath.to_string real_exe; "switch" ]
    | cmd :: "switch" :: first_arg :: rest_args
      when is_opam_exe cmd
           && String.length first_arg > 2
           && String.is_prefix ~affix:"--" first_arg ->
        Logs.debug (fun l ->
            l
              "Detected [opam switch --some-option ...] invocation. Not using \
               'env opam switch' so Opam can discover the parent shell");
        let* _abs_cmd_p, real_exe = get_abs_cmd_and_real_exe ~opam:() cmd in
        Ok ([ Fpath.to_string real_exe; "switch"; first_arg ] @ rest_args)
    | cmd :: "switch" :: "list" :: args when is_opam_exe cmd ->
        Logs.debug (fun l ->
            l
              "Detected [opam switch list ...] invocation. Not using 'env opam \
               switch' so Opam can discover the parent shell");
        let* _abs_cmd_p, real_exe = get_abs_cmd_and_real_exe ~opam:() cmd in
        Ok ([ Fpath.to_string real_exe; "switch"; "list" ] @ args)
    (* CMDLINE_C FORM *)
    | cmd :: args ->
        let opam = if is_opam_exe cmd then Some () else None in
        let* () = if is_blurb_exe cmd && args = [] then blurb () else Ok () in
        let* abs_cmd_p, real_exe = get_abs_cmd_and_real_exe ?opam cmd in
        let* bytecode_exe = is_bytecode_exe abs_cmd_p in
        let* () =
          match (opam, bytecode_exe) with
          | Some (), _ ->
              (* opam should never set OCAMLFIND_CONF, etc. *)
              Ok ()
          | None, true ->
              (* bytecode_exe *)
              Logs.debug (fun l ->
                  l
                    "Detected precompiled invocation of non-opam command. \
                     Setting environment to have relocatable findlib \
                     configuration and stub libraries");
              set_precompiled_env abs_cmd_p
          | None, false ->
              (* not bytecode_exe *)
              Logs.debug (fun l ->
                  l
                    "Detected enduser invocation of non-opam command. Setting \
                     environment to have install-time findlib configuration");
              set_enduser_env abs_cmd_p
        in
        Ok ([ Fpath.to_string env_exe; Fpath.to_string real_exe ] @ args)
    | _ ->
        Rresult.R.error_msgf "You need to supply a command, like `%s bash`"
          OS.Arg.exec
  in
  Cmd.of_list cmd_and_args
