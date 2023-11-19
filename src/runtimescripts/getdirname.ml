let () =
  match Array.length Sys.argv with
  | 1 ->
      prerr_endline "usage: getdirname <PATH> [subdir1 [subdir2 ...]]";
      exit 1
  | 2 ->
      let path = Sys.argv.(1) in
      print_endline (Filename.dirname path)
  | n ->
      let path = Sys.argv.(1) in
      for i = 2 to n - 1 do
        print_endline Filename.(concat (dirname path) Sys.argv.(i))
      done
