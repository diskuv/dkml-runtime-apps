val extract_dkml_scripts :
  dkmlversion:string -> Fpath.t -> (unit, Rresult.R.msg) result

(** [portable_delete_file] deletes the file even it is read-only on Windows.
    Works around https://github.com/dbuenzli/bos/issues/98 *)
val portable_delete_file : Fpath.t -> (unit, Rresult.R.msg) result
