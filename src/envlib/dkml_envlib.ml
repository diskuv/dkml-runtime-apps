open Dkml_envlib_intf
module Envlib_dependencies_lite = Envlib_dependencies_lite

module Make (Deps : ENVLIB_DEPENDENCIES) = struct
  open Deps.Rresult
  open Deps.Sexplib
  open Deps.Bos

  let association_list_of_sexp_lists =
    Conv.list_of_sexp
      (Conv.pair_of_sexp Conv.string_of_sexp
         (Conv.list_of_sexp Conv.string_of_sexp))

  let association_list_of_sexp =
    Conv.list_of_sexp
      (Conv.pair_of_sexp Conv.string_of_sexp Conv.string_of_sexp)

  (** Mimics set_dkmlparenthomedir *)
  let get_dkmlparenthomedir =
    lazy
      (let open OS.Env in
      match req_var "LOCALAPPDATA" with
      | Ok localappdata ->
          Deps.Fpath.of_string localappdata >>| fun fp ->
          Deps.Fpath.(fp / "Programs" / "DiskuvOCaml")
      | Error _ -> (
          match req_var "XDG_DATA_HOME" with
          | Ok xdg_data_home ->
              Deps.Fpath.of_string xdg_data_home >>| fun fp ->
              Deps.Fpath.(fp / "diskuv-ocaml")
          | Error _ -> (
              match req_var "HOME" with
              | Ok home ->
                  Deps.Fpath.of_string home >>| fun fp ->
                  Deps.Fpath.(fp / ".local" / "share" / "diskuv-ocaml")
              | Error _ as err -> err)))

  (** [get_dkmlvars_opt] gets an association list of dkmlvars-v2.sexp *)
  let get_dkmlvars_opt =
    lazy
      ( Lazy.force get_dkmlparenthomedir >>= fun fp ->
        OS.File.exists Deps.Fpath.(fp / "dkmlvars-v2.sexp") >>| fun exists ->
        if exists then
          Some
            (Sexp.load_sexp_conv_exn
               Deps.Fpath.(fp / "dkmlvars-v2.sexp" |> to_string)
               association_list_of_sexp_lists)
        else None )

  (** Get MSYS2 directory *)
  let get_msys2_dir_opt =
    lazy
      (Lazy.force get_dkmlvars_opt >>= function
       | None -> Ok None
       | Some assocl -> (
           match List.assoc_opt "DiskuvOCamlMSYS2Dir" assocl with
           | Some [ v ] -> Deps.Fpath.of_string v >>= fun fp -> Ok (Some fp)
           | Some _ | None -> Ok None))

  (* [get_dkmlvars] gets an association list of dkmlvars-v2.sexp *)
  let get_dkmlvars =
    lazy
      ( Lazy.force get_dkmlparenthomedir >>| fun fp ->
        Sexp.load_sexp_conv_exn
          Deps.Fpath.(fp / "dkmlvars-v2.sexp" |> to_string)
          association_list_of_sexp_lists )

  (* Get DKML version *)
  let get_dkmlversion =
    lazy
      ( Lazy.force get_dkmlvars >>= fun assocl ->
        match List.assoc_opt "DiskuvOCamlVersion" assocl with
        | Some [ v ] -> Ok v
        | Some _ ->
            R.error_msg
              "More or less than one DiskuvOCamlVersion in dkmlvars-v2.sexp"
        | None -> R.error_msg "No DiskuvOCamlVersion in dkmlvars-v2.sexp" )

  (* Get Diskuv OCaml home directory *)
  let get_dkmlhome_dir_opt =
    lazy
      (Lazy.force get_dkmlvars_opt >>= function
       | None -> Ok None
       | Some assocl -> (
           match List.assoc_opt "DiskuvOCamlHome" assocl with
           | Some [ v ] -> Deps.Fpath.of_string v >>= fun fp -> Ok (Some fp)
           | Some _ | None -> Ok None))

  (* Get Diskuv OCaml home directory *)
  let get_dkmlhome_dir =
    lazy
      ( Lazy.force get_dkmlvars >>= fun assocl ->
        match List.assoc_opt "DiskuvOCamlHome" assocl with
        | Some [ v ] -> Deps.Fpath.of_string v >>= fun fp -> Ok fp
        | Some _ ->
            R.error_msg
              "More or less than one DiskuvOCamlHome in dkmlvars-v2.sexp"
        | None -> R.error_msg "No DiskuvOCamlHome in dkmlvars-v2.sexp" )
end