open Configurator.V1
open Bos

let c_compile_obj ~ccomp_type ~native_c_compiler =
  let cmd_native_c_compiler = Rresult.R.error_msg_to_invalid_arg (Cmd.of_string native_c_compiler) in
  let cmd = if ccomp_type = "msvc" then
      Cmd.(cmd_native_c_compiler % "confdir.c" % ("-Feconfdir.exe") % "-link" % "Ole32.lib" % "shell32.lib")
    else Cmd.(cmd_native_c_compiler % "confdir.c" % "-o" % "confdir") in
  (Cmd.get_line_tool cmd) :: Cmd.line_args cmd

let () =
  main ~name:"runner" (fun c ->
      let ccomp_type = ocaml_config_var_exn c "ccomp_type" in
      let native_c_compiler = ocaml_config_var_exn c "native_c_compiler" in
      Flags.write_lines "c-compile-exe.lines.txt" (c_compile_obj ~ccomp_type ~native_c_compiler)
    )
