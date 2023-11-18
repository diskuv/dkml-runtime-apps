module Dkml_environment = Dkml_environment

module Monadic_operators : sig
  val ( >>= ) : ('a, 'b) result -> ('a -> ('c, 'b) result) -> ('c, 'b) result
  val ( >>| ) : ('a -> 'b) -> ('a, 'c) result -> ('b, 'c) result
end

val int_parser : int Bos.OS.Env.parser
val get_msys2_dir_opt : (Fpath.t option, Rresult.R.msg) result lazy_t
val get_dkmlhome_dir_opt : (Fpath.t option, Rresult.R.msg) result lazy_t
val get_dkmlversion : (string, Rresult.R.msg) result lazy_t

type dkmlmode = Nativecode | Bytecode

val pp_dkmlmode : Format.formatter -> dkmlmode -> unit
val get_dkmlmode : (dkmlmode, Rresult.R.msg) result lazy_t
val association_list_of_sexp : Sexplib.Sexp.t -> (string * string) list

val get_opam_switch_prefix : (Fpath.t, Rresult.R.msg) result lazy_t
(** [get_opam_switch_prefix] is a lazy function that gets the OPAM_SWITCH_PREFIX environment variable.
    If OPAM_SWITCH_PREFIX is not found, then a fallback to <OPAMROOT>/playground is used instead. *)
