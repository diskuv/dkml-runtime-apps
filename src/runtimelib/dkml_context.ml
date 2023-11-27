open Bos
open Rresult
open Sexplib

let association_list_of_sexp_lists =
  Conv.list_of_sexp
    (Conv.pair_of_sexp Conv.string_of_sexp
       (Conv.list_of_sexp Conv.string_of_sexp))

let association_list_of_sexp =
  Conv.list_of_sexp (Conv.pair_of_sexp Conv.string_of_sexp Conv.string_of_sexp)

(* Mimics paths from [set_dkmlparenthomedir] and also dkml-install-api's [program_name] paths *)
let program_path ~camel_cased ~kebab_cased =
  let open OS.Env in
  match (Sys.win32, var "LOCALAPPDATA") with
  | true, Some localappdata when String.length localappdata > 0 ->
      Fpath.of_string localappdata >>| fun fp ->
      Fpath.(fp / "Programs" / camel_cased)
  | _ -> (
      match var "XDG_DATA_HOME" with
      | Some xdg_data_home when String.length xdg_data_home > 0 ->
          Fpath.of_string xdg_data_home >>| fun fp -> Fpath.(fp / kebab_cased)
      | _ -> (
          match req_var "HOME" with
          | Ok home ->
              Fpath.of_string home >>| fun fp ->
              if String.equal Dkml_config.ocaml_system "macosx" then
                Fpath.(fp / "Applications" / camel_cased)
              else Fpath.(fp / ".local" / "share" / kebab_cased)
          | Error _ as err -> err))

(* Mimics set_dkmlparenthomedir *)
let get_dkmlparenthomedir =
  lazy (program_path ~camel_cased:"DkML" ~kebab_cased:"dkml")

(** [get_vsstudio_dir_opt] gets the DkML configured Visual Studio
    installation directory. [dkml init --system] is one place where
    Visual Studio is located and cached; in general the responsibility
    is performed by cache-vsstudio.ps1. *)
let get_vsstudio_dir_opt =
  Lazy.from_fun (fun () ->
      let ( let* ) = Result.bind in
      let* dkml_home_fp = Lazy.force get_dkmlparenthomedir in
      let txt_fp = Fpath.(dkml_home_fp / "vsstudio.dir.txt") in
      let* txt_exists = OS.File.exists txt_fp in
      if txt_exists then
        let* txt_contents = OS.File.read txt_fp in
        let txt_contents = String.trim txt_contents in
        let* vsstudio_dir_fp = Fpath.of_string txt_contents in
        Ok (Some vsstudio_dir_fp)
      else Ok None)

(** [get_dkmlenv_opt] creates an association list in the format of
    dkmlvars-v2.sexp from the environment if DiskuvOCamlVarsVersion and
    DiskuvOCamlVersion are defined. These two environment variables are all
    that is set for Unix in diskuv-runtime-distribution's init-opam-root.sh.

    These environment values must be used during an upgrade (or else the
    upgrade can use old installation values) or an install (where
    dkmlvars-v2.sexp is not present) like in setup-userprofile.ps1. *)
let get_dkmlenv_opt =
  Lazy.from_fun (fun () ->
      match OS.Env.(var "DiskuvOCamlVarsVersion", var "DiskuvOCamlVersion") with
      (* Blanks are treated the same as None *)
      | None, None | Some _, None | None, Some _ | Some "", _ | _, Some "" ->
          Ok None
      | Some "2", Some ver ->
          let open Sexp in
          let lst = [] in
          let lst =
            match OS.Env.var "DiskuvOCamlHome" with
            | None | Some "" -> lst
            | Some v -> List [ Atom "DiskuvOCamlHome"; List [ Atom v ] ] :: lst
          in
          let lst =
            match OS.Env.var "DiskuvOCamlMSYS2Dir" with
            | None | Some "" -> lst
            | Some v ->
                List [ Atom "DiskuvOCamlMSYS2Dir"; List [ Atom v ] ] :: lst
          in
          let lst =
            match OS.Env.var "DiskuvOCamlDeploymentId" with
            | None | Some "" -> lst
            | Some v ->
                List [ Atom "DiskuvOCamlDeploymentId"; List [ Atom v ] ] :: lst
          in
          let lst =
            match OS.Env.var "DiskuvOCamlBinaryPaths" with
            | None | Some "" -> lst
            | Some v ->
                let bpaths =
                  Astring.String.cuts ~sep:";" v
                  |> List.map (fun bpath -> Atom bpath)
                in
                List [ Atom "DiskuvOCamlBinaryPaths"; List bpaths ] :: lst
          in
          let lst =
            match OS.Env.var "DiskuvOCamlMode" with
            | None | Some "" -> lst
            | Some v -> List [ Atom "DiskuvOCamlMode"; List [ Atom v ] ] :: lst
          in
          Ok
            (Some
               (List
                  ([
                     List [ Atom "DiskuvOCamlVarsVersion"; List [ Atom "2" ] ];
                     List [ Atom "DiskuvOCamlVersion"; List [ Atom ver ] ];
                   ]
                  @ lst)))
      | Some varsver, Some _ ->
          R.error_msgf
            "Only version of DiskuvOCamlVarsVersion currently supported is 2, \
             not %s"
            varsver)

(** [get_dkmlvars_opt] gets an association list of dkmlvars-v2.sexp.
    
    If DiskuvOCaml* environment variables are found, those environment
    variables are used and the file system is not accessed.

    Otherwise the canonical filesystem location of dkmlvars-v2.sexp
    is used. *)
let get_dkmlvars_opt =
  Lazy.from_fun (fun () ->
      Lazy.force get_dkmlenv_opt >>= fun env_opt ->
      match env_opt with
      | Some env -> Ok (Some (association_list_of_sexp_lists env))
      | None ->
          Lazy.force get_dkmlparenthomedir >>= fun fp ->
          OS.File.exists Fpath.(fp / "dkmlvars-v2.sexp") >>| fun exists ->
          if exists then
            Some
              (Sexp.load_sexp_conv_exn
                 Fpath.(fp / "dkmlvars-v2.sexp" |> to_string)
                 association_list_of_sexp_lists)
          else None)

(** [get_dkmlvars] gets an association list of dkmlvars-v2.sexp.
    
    If DiskuvOCaml* environment variables are found, those environment
    variables are used and the file system is not accessed.

    Otherwise the canonical filesystem location of dkmlvars-v2.sexp
    is used. *)
let get_dkmlvars =
  Lazy.from_fun (fun () ->
      Lazy.force get_dkmlenv_opt >>= fun env_opt ->
      match env_opt with
      | Some env -> Ok (association_list_of_sexp_lists env)
      | None ->
          Lazy.force get_dkmlparenthomedir >>| fun fp ->
          Sexp.load_sexp_conv_exn
            Fpath.(fp / "dkmlvars-v2.sexp" |> to_string)
            association_list_of_sexp_lists)

(* Get DkML version. Defaults to the compiled DkML version. *)
let get_dkmlversion_or_default =
  lazy
    (Lazy.force get_dkmlvars_opt >>= function
     | None -> R.ok Dkml_config.version
     | Some assocl -> (
         match List.assoc_opt "DiskuvOCamlVersion" assocl with
         | Some [ v ] -> R.ok v
         | None | Some [] -> R.ok Dkml_config.version
         | Some _ ->
             R.error_msg "More than one DiskuvOCamlVersion in dkmlvars-v2.sexp"))

type dkmlmode = Nativecode | Bytecode

let pp_dkmlmode fmt = function
  | Nativecode -> Fmt.pf fmt "Nativecode"
  | Bytecode -> Fmt.pf fmt "Bytecode"

(* Get DkML mode. Defaults to nativecode *)
let get_dkmlmode_or_default =
  lazy
    (Lazy.force get_dkmlvars_opt >>= function
     | None -> R.ok Nativecode
     | Some assocl -> (
         match List.assoc_opt "DiskuvOCamlMode" assocl with
         | Some [ "native" ] -> R.ok Nativecode
         | Some [ "byte" ] -> R.ok Bytecode
         | Some [ v ] ->
             R.error_msg
               ("Only native and byte are allowed as the DiskuvOCamlMode in \
                 dkmlvars-v2.sexp, not " ^ v)
         | None | Some [] -> R.ok Nativecode
         | Some _ ->
             R.error_msg
               "More or less than one DiskuvOCamlMode in dkmlvars-v2.sexp"))

(* Get MSYS2 directory *)
let get_msys2_dir_opt =
  lazy
    (Lazy.force get_dkmlvars_opt >>= function
     | None -> R.ok None
     | Some assocl -> (
         match List.assoc_opt "DiskuvOCamlMSYS2Dir" assocl with
         | Some [ v ] -> Fpath.of_string v >>= fun fp -> R.ok (Some fp)
         | Some _ | None -> R.ok None))

(* Get MSYS2 directory *)
let get_msys2_dir =
  lazy
    ( Lazy.force get_dkmlvars >>= fun assocl ->
      match List.assoc_opt "DiskuvOCamlMSYS2Dir" assocl with
      | Some [ v ] -> Fpath.of_string v >>= fun fp -> R.ok fp
      | Some _ ->
          R.error_msg
            "More or less than one DiskuvOCamlMSYS2Dir in dkmlvars-v2.sexp"
      | None -> R.error_msg "No DiskuvOCamlMSYS2Dir in dkmlvars-v2.sexp" )

(* Get DkML home directory *)
let get_dkmlhome_dir_opt =
  lazy
    (Lazy.force get_dkmlvars_opt >>= function
     | None -> R.ok None
     | Some assocl -> (
         match List.assoc_opt "DiskuvOCamlHome" assocl with
         | Some [ v ] -> Fpath.of_string v >>= fun fp -> R.ok (Some fp)
         | Some _ | None -> R.ok None))

(* Get DkML home directory or the default *)
let get_dkmlhome_dir_or_default =
  let get_default () =
    Lazy.force get_dkmlmode_or_default >>= fun dkmlmode ->
    match dkmlmode with
    | Nativecode ->
        (* Confer: dkml-installer-ocaml/i-network/src/private_common.ml *)
        program_path ~camel_cased:"DkMLNative" ~kebab_cased:"dkml-native"
    | Bytecode ->
        (* Confer: dkml-installer-ocaml-byte/i-offline/src/private_common.ml *)
        program_path ~camel_cased:"DkMLByte" ~kebab_cased:"dkml-byte"
  in
  lazy
    (Lazy.force get_dkmlvars_opt >>= function
     | None -> get_default ()
     | Some assocl -> (
         match List.assoc_opt "DiskuvOCamlHome" assocl with
         | Some [ v ] -> Fpath.of_string v >>= fun fp -> R.ok fp
         | None | Some [] -> get_default ()
         | Some _ ->
             R.error_msg "More than one DiskuvOCamlHome in dkmlvars-v2.sexp"))
