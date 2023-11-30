open Bos

let portable_delete_file target_fp =
  let ( let* ) = Result.bind in
  (* [doc from diskuvbox]
     [tracks https://github.com/dbuenzli/bos/issues/98]
     For Windows, can't write without turning off read-only flag.
     In fact, you can still get Permission Denied even after turning
     off read-only flag, perhaps because Windows has a richer
     permissions model than POSIX. So we remove the file
     after turning off read-only *)
  if Sys.win32 then
    let* exists = OS.File.exists target_fp in
    if exists then
      let* () = OS.Path.Mode.set target_fp 0o644 in
      OS.File.delete target_fp
    else Ok ()
  else OS.File.delete target_fp

let extract_dkml_scripts ~dkmlversion dir_fp =
  let ( let* ) = Result.bind in
  let file_list_helper file_list read subdir_fp =
    let dest_fp = Fpath.(dir_fp // subdir_fp |> normalize) in
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
            let script_opt = read filename in
            Logs.debug (fun l ->
                l "[extract_dkml_scripts] <%a> %s present=%b" Fpath.pp subdir_fp
                  filename
                  (Option.is_some script_opt));
            Option.fold ~none:(Result.Ok ())
              ~some:(fun script ->
                let* () =
                  (* [doc from diskuvbox]
                     [tracks https://github.com/dbuenzli/bos/issues/98]
                     For Windows, can't write without turning off read-only flag.
                     In fact, you can still get Permission Denied even after turning
                     off read-only flag, perhaps because Windows has a richer
                     permissions model than POSIX. So we remove the file
                     after turning off read-only *)
                  if Sys.win32 then
                    let* exists = OS.File.exists target_fp in
                    if exists then
                      let* () = OS.Path.Mode.set target_fp 0o644 in
                      OS.File.delete target_fp
                    else Ok ()
                  else Ok ()
                in
                OS.File.write ~mode:0x755 target_fp script)
              script_opt
        | Error _ as err -> err)
      (Result.Ok ()) file_list
  in
  (* extract everything from Dkml_scripts *)
  let* () =
    file_list_helper Dkml_scripts.file_list Dkml_scripts.read Fpath.(v ".")
  in
  (* extract everything from Dkml_compiler_src into vendor/dkml-compiler *)
  let* () =
    file_list_helper Dkml_compiler_src.file_list Dkml_compiler_src.read
      Fpath.(v "vendor" / "dkml-compiler")
  in
  (* create .dkmlroot from template.dkmlroot *)
  let path = "vendor/drc/template.dkmlroot" in
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
  | None -> Rresult.R.error_msgf "Could not read the DkML script %s" path
