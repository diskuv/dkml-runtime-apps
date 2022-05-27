(** Analogs of external OCaml packages *)
module type ENVLIB_DEPENDENCIES = sig
  module Rresult : sig
    val ( >>= ) : ('a, 'b) result -> ('a -> ('c, 'b) result) -> ('c, 'b) result

    val ( >>| ) : ('a, 'b) result -> ('a -> 'c) -> ('c, 'b) result

    module R : sig
      type msg = [ `Msg of string ]

      val error_msg : string -> ('a, [> msg ]) result
      (** [error_msg s] is [error (`Msg s)]. *)

      val pp_msg : Format.formatter -> msg -> unit
      (** [pp_msg ppf m] prints [m] on [ppf]. *)
    end
  end

  module Fpath : sig
    type t

    val of_string : string -> (t, Rresult.R.msg) result

    val to_string : t -> string

    val pp : Format.formatter -> t -> unit

    val ( / ) : t -> string -> t

    val filename : t -> string
    (** [filename p] is the file name of [p]. This is the last segment of
        [p] if [p] is a {{!is_file_path}file path}, and undefined
        otherwise. *)

    val split_base : t -> t * t
    (** [split_base p] splits [p] into a directory [d] and a {e relative}
        base path [b] *)

    val split_ext : ?multi:bool -> t -> t * string
    (** [split_ext ?multi p] is [(rem_ext ?multi p, get_ext ?multi p)]. *)

    val compare : t -> t -> int
    (** [compare p p'] is a total order on paths compatible with {!equal}. *)
  end

  module Bos : sig
    module Cmd : sig
      type t

      val v : string -> t

      val of_list : ?slip:string -> string list -> t
    end

    module OS : sig
      module Cmd : sig
        val get_tool :
          ?search:Fpath.t list -> Cmd.t -> (Fpath.t, Rresult.R.msg) result
        (** [get_tool cmd] is like {!find_tool} except it errors if the
              tool path cannot be found. *)
      end

      module Env : sig
        type 'a parser = string -> ('a, Rresult.R.msg) result
        (** The type for environment variable value parsers. *)

        val req_var : string -> (string, Rresult.R.msg) result

        val opt_var : string -> absent:string -> string
        (** [opt_var name absent] is the value of the optionally defined
            environment variable [name] if defined and [absent] if
            undefined. *)

        val set_var : string -> string option -> (unit, Rresult.R.msg) result
        (** [set_var name v] sets the environment variable [name] to [v]. *)

        val parse :
          string -> 'a parser -> absent:'a -> ('a, Rresult.R.msg) result
        (** [parse name p ~absent] is:
          {ul
          {- [Ok absent] if [Env.var name = None]}
          {- [Ok v] if [Env.var name = Some s] and [p s = Ok v]}
          {- [Error (`Msg m)] otherwise with [m] an error message
             that mentions [name] and the parse error of [p].}} *)

        val path : Fpath.t parser
        (** [path s] is a path parser using {!Fpath.of_string}. *)
      end

      module File : sig
        val exists : Fpath.t -> (bool, Rresult.R.msg) result

        val null : Fpath.t
        (** [null] is [Fpath.v "/dev/null"] on POSIX and [Fpath.v "NUL"] on
        Windows. It represents a file on the OS that discards all
        writes and returns end of file on reads. *)
      end

      module Dir : sig
        val exists : Fpath.t -> (bool, Rresult.R.msg) result
      end
    end
  end

  module Sexplib : sig
    module Sexp : sig
      type t

      val load_sexp_conv_exn :
        ?strict:bool -> ?buf:bytes -> string -> (t -> 'a) -> 'a
    end

    module Conv : sig
      val list_of_sexp : (Sexp.t -> 'a) -> Sexp.t -> 'a list

      val pair_of_sexp : (Sexp.t -> 'a) -> (Sexp.t -> 'b) -> Sexp.t -> 'a * 'b

      val string_of_sexp : Sexp.t -> string
    end
  end
end
