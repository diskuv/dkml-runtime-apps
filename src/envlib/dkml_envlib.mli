open Dkml_envlib_intf

module Envlib_dependencies_lite : ENVLIB_DEPENDENCIES
(** You can use this for a light-weight set of dependencies ... no other
    OCaml package is needed. However you will get more robust error
    reporting, etc., if you supply real dependencies on ["bos"]
    and ["rresult"] and ["sexplib"]. *)

module Make : functor (Deps : ENVLIB_DEPENDENCIES) -> sig
  val association_list_of_sexp_lists :
    Deps.Sexplib.Sexp.t -> (string * string list) list

  val association_list_of_sexp : Deps.Sexplib.Sexp.t -> (string * string) list

  val get_dkmlparenthomedir : (Deps.Fpath.t, Deps.Rresult.R.msg) result lazy_t

  val get_dkmlvars_opt :
    ((string * string list) list option, Deps.Rresult.R.msg) result lazy_t

  val get_msys2_dir_opt :
    (Deps.Fpath.t option, Deps.Rresult.R.msg) result lazy_t

  val get_dkmlhome_dir_opt : (Deps.Fpath.t option, Deps.Rresult.R.msg) result lazy_t

  val get_dkmlversion : (string, Deps.Rresult.R.msg) result lazy_t

  val get_dkmlhome_dir : (Deps.Fpath.t, Deps.Rresult.R.msg) result lazy_t
end
