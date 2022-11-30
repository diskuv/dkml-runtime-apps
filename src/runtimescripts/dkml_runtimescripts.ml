open Bos

let extract_dkml_scripts dir_fp =
  let ( >>= ) = Result.bind in
  List.fold_left
    (fun acc filename ->
       match acc with
       | Ok _ ->
         (* mkdir (parent filename) *)
         Fpath.of_string filename >>= fun filename_fp ->
         let target_fp = Fpath.(dir_fp // filename_fp) in
         let target_dir_fp = Fpath.(parent target_fp) in
         OS.Dir.create target_dir_fp |> ignore;
         (* cp script filename *)
         let script_opt = Dkml_scripts.read filename in
         Option.fold ~none:(Result.Ok ())
           ~some:(fun script -> OS.File.write ~mode:0x755 target_fp script)
           script_opt
       | Error _ as err -> err)
    (Result.Ok ()) Dkml_scripts.file_list
  >>= fun () ->
  (* cp <builtin> .dkmlroot *)
  let path = "vendor/dkml-compiler/template.dkmlroot" in
  match Dkml_scripts.read path with
  | Some v ->
    let template = String.trim @@ v in
    OS.File.write Fpath.(dir_fp // v ".dkmlroot") template
  | None -> Rresult.R.error_msgf "Could not read the DKML script %s" path
