let (let*) = Result.bind
let dos2unix s = Astring.(String.concat ~sep:"\n" @@ String.cuts ~sep:"\r\n" s)
let () = Result.get_ok @@ Bos.OS.File.(
  let* contents = read (Fpath.v Sys.argv.(1)) in
  write (Fpath.v Sys.argv.(2)) (dos2unix contents)
)