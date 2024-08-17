include Dkml_context
include Opam_context
module Dkml_environment = Dkml_environment
module Dkml_news = Dkml_news
module Dkml_use = Dkml_use
module Dkml_cli = Dkml_cli
module SystemConfig = Opam_context.SystemConfig

module Monadic_operators = struct
  (* Result monad operators *)
  let ( >>= ) = Result.bind
  let ( >>| ) = Result.map
end

let version = Dkml_config.version
let init_nativecode_system = Init_system.init_nativecode_system
