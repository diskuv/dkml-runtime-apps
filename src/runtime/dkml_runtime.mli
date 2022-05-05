(*
val association_list_of_sexp_lists :
  Sexplib0__.Sexp.t -> (string * string list) list
val get_dkmlparenthomedir : (Fpath.t, Rresult.R.msg) result lazy_t
val get_dkmlvars_opt :
  ((string * string list) list option, Rresult.R.msg) result lazy_t
val get_dkmlvars : ((string * string list) list, Rresult.R.msg) result lazy_t
val get_msys2_dir : (Fpath.t, Rresult.R.msg) result lazy_t
val dkmlroot_contents : string
module Dkml_scripts = Dkml_runtime__.Scripts
*)

module Dkml_environment = Dkml_environment

module Monadic_operators : sig
  val ( >>= ) : ('a, 'b) result -> ('a -> ('c, 'b) result) -> ('c, 'b) result

  val ( >>| ) : ('a -> 'b) -> ('a, 'c) result -> ('b, 'c) result
end

val int_parser : int Bos.OS.Env.parser

val extract_dkml_scripts : Fpath.t -> (unit, Rresult.R.msg) result

val get_msys2_dir_opt : (Fpath.t option, Rresult.R.msg) result lazy_t

val get_dkmlhome_dir_opt : (Fpath.t option, Rresult.R.msg) result lazy_t

val get_dkmlversion : (string, Rresult.R.msg) result lazy_t

val get_dkmlhome_dir : (Fpath.t, Rresult.R.msg) result lazy_t

val association_list_of_sexp : Sexplib0__.Sexp.t -> (string * string) list
