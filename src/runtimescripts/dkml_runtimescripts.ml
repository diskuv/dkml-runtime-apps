open Bos

let extract_dkml_scripts ~dkmlversion dir_fp =
  let ( let* ) = Result.bind in
  let file_list_helper file_list dest_fp =
    List.fold_left
      (fun acc filename ->
        match acc with
        | Ok _ ->
            (* mkdir (parent filename) *)
            let* filename_fp = Fpath.of_string filename in
            let target_fp = Fpath.(dest_fp // filename_fp) in
            let target_dir_fp = Fpath.(parent target_fp) in
            OS.Dir.create target_dir_fp |> ignore;
            (* cp script filename *)
            let script_opt = Dkml_scripts.read filename in
            Option.fold ~none:(Result.Ok ())
              ~some:(fun script -> OS.File.write ~mode:0x755 target_fp script)
              script_opt
        | Error _ as err -> err)
      (Result.Ok ()) file_list
  in
  (* extract everything from Dkml_scripts *)
  let* () = file_list_helper Dkml_scripts.file_list dir_fp in
  (* extract everything from Dkml_compiler_src into vendor/dkml-compiler *)
  let* () =
    file_list_helper Dkml_compiler_src.file_list
      Fpath.(dir_fp / "vendor" / "dkml-compiler")
  in
  (* create .dkmlroot from template.dkmlroot *)
  let path = "vendor/dkml-compiler/template.dkmlroot" in
  match Dkml_scripts.read path with
  | Some v ->
      let template = String.trim @@ v in
      (* change dkml_root_version *)
      let new_dkml_root_version_line = "dkml_root_version=" ^ dkmlversion in
      let regexp =
        Re.(compile (seq [ bol; str "dkml_root_version="; rep notnl ]))
      in
      let template' =
        Re.replace_string regexp ~by:new_dkml_root_version_line template
      in
      Logs.debug (fun l -> l "@[.dkmlroot:@]@,@[  %a@]" Fmt.lines template');
      (* write modified .dkmlroot *)
      OS.File.write Fpath.(dir_fp // v ".dkmlroot") template'
  | None -> Rresult.R.error_msgf "Could not read the DKML script %s" path
