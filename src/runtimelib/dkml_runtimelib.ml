open Bos
open Astring
include Dkml_context
include Opam_context
module Dkml_environment = Dkml_environment
module Dkml_news = Dkml_news
module SystemConfig = Opam_context.SystemConfig

module Monadic_operators = struct
  (* Result monad operators *)
  let ( >>= ) = Result.bind
  let ( >>| ) = Result.map
end

let int_parser = OS.Env.(parser "int" String.to_int)
let version = Dkml_config.version
let init_nativecode_system = Init_system.init_nativecode_system
