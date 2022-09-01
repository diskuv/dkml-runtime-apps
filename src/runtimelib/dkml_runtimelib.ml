open Bos
open Astring
include Dkml_context
module Dkml_environment = Dkml_environment

module Monadic_operators = struct
  (* Result monad operators *)
  let ( >>= ) = Result.bind

  let ( >>| ) = Result.map
end

let int_parser = OS.Env.(parser "int" String.to_int)
