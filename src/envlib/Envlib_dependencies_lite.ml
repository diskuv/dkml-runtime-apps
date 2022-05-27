module Rresult = struct
  let ( >>= ) = Result.bind

  let ( >>| ) f x = Result.map x f

  module R = struct
    type msg = [ `Msg of string ]

    let error_msg s = Error (`Msg s)

    let pp_msg ppf = function
      | `Msg s -> Format.fprintf ppf "%s" s
      | _ -> Format.fprintf ppf "An unknown result occurred that was not a `Msg"
  end
end

module Fpath = struct
  type t = string

  let v fp =
    (* Convert any Windows forward slashes into backslashes *)
    String.map (function '\\' -> '/' | c -> c) fp

  let of_string fp = Ok (v fp)

  let to_string t =
    if Sys.win32 then
      (* Convert any backslashes into forward slashes *)
      String.map (function '/' -> '\\' | c -> c) t
    else t

  let pp = Format.pp_print_string

  let ( / ) x y = x ^ "/" ^ y

  let filename t = Filename.basename t

  let split_base p =
    let d = Filename.dirname p and b = Filename.basename p in
    (d, b)

  let split_ext ?multi p =
    if multi = Some true then
      failwith "The lite dependencies do not support [split_ext ~multi:true]"
    else
      let d = Filename.dirname p and b = Filename.basename p in
      let e1 = Filename.remove_extension b in
      let e2 = Filename.extension b in
      (d ^ "/" ^ e1, e2)

  let compare p1 p2 = String.compare p1 p2
end

let split_path () =
  match Sys.getenv_opt "PATH" with
  | None -> []
  | Some path ->
      let sep = if Sys.win32 then ';' else ':' in
      String.split_on_char sep path

module Bos = struct
  module Cmd = struct
    type t = string list

    let v s = [ s ]

    let of_list ?slip l =
      match slip with
      | None -> l
      | Some _ ->
          failwith
            "The lite implementation does not allow [Cmd.of_list ~slip:...]"
  end

  module OS = struct
    module Cmd = struct
      let l_exe = String.length ".exe"

      let exe_exists p =
        let l_p = String.length p in
        if l_p > l_exe && String.sub p (l_p - l_exe) l_exe = ".exe" then
          (* ends with .exe; try exact match *)
          match Sys.file_exists p with true -> Some p | false -> None
        else
          (* does not end with .exe, so try both itself and itself.exe *)
          match Sys.file_exists p with
          | true -> Some p
          | false -> (
              let p_exe = p ^ ".exe" in
              match Sys.file_exists p_exe with
              | true -> Some p_exe
              | false -> None)

      let get_tool ?search = function
        | [] ->
            Rresult.R.error_msg
              "You must supply a non-empty commmand in [get_tool cmd]"
        | cmd :: _args -> (
            if
              (* is cmd an absolute (ex. /x/y/z) or relative (ex. ./x) path? *)
              String.contains cmd '/' || String.contains cmd '\\'
            then
              match exe_exists cmd with
              | Some p -> Ok p
              | None ->
                  Rresult.R.error_msg
                    (Format.sprintf "The tool [%s] does not exist" cmd)
            else
              (* cmd is a bareword (ex. dune), so search in PATH or ?search *)
              let paths =
                match search with None -> split_path () | Some ps -> ps
              in
              match List.filter_map exe_exists paths with
              | [] ->
                  Rresult.R.error_msg
                    (Format.sprintf "The tool [%s] was not found in the PATH %s"
                       cmd (String.concat "\n" paths))
              | first :: _rest -> Ok first)
    end

    module Env = struct
      type 'a parser = string -> ('a, Rresult.R.msg) result

      let req_var name =
        match Sys.getenv_opt name with
        | None | Some "" ->
            Rresult.R.error_msg
              (Format.sprintf "The environment value '%s' was not found" name)
        | Some v -> Ok v

      let opt_var name ~absent =
        match Sys.getenv_opt name with None | Some "" -> absent | Some s -> s

      let set_var name = function
        | Some v ->
            Unix.putenv name v;
            Ok ()
        | None ->
            Unix.putenv name "";
            Ok ()

      let parse name p ~absent =
        match Sys.getenv_opt name with
        | None | Some "" -> Ok absent
        | Some s -> (
            match p s with
            | Ok v -> Ok v
            | Error msg ->
                Rresult.R.error_msg
                  (Format.asprintf
                     "Could not parse the environment variable [%s]. Received \
                      error: %a"
                     name Rresult.R.pp_msg msg))

      let path = Fpath.of_string
    end

    module File = struct
      let exists fp = Ok (Sys.file_exists fp)

      let null = if Sys.win32 then Fpath.v "NUL" else Fpath.v "/dev/null"
    end

    module Dir = struct
      let exists fp = Ok (Sys.is_directory fp)
    end
  end
end

module Sexplib = struct
  module Sexp = struct
    type t = CCSexp.t

    let load_sexp_conv_exn ?strict:_ ?buf:_ file f =
      match CCSexp.parse_file file with
      | Error err ->
          failwith
            (Format.sprintf "Could not load the s-exp from %s: %s" file err)
      | Ok sexp -> f sexp
  end

  module Conv = struct
    let list_of_sexp conv = function
      | `List l -> List.map conv l
      | sexp ->
          failwith (Format.asprintf "Instead of a list, got: %a" CCSexp.pp sexp)

    let pair_of_sexp conv1 conv2 = function
      | `List [ item1; item2 ] -> (conv1 item1, conv2 item2)
      | sexp ->
          failwith
            (Format.asprintf
               "Instead of a pair (a list of two elements), got: %a" CCSexp.pp
               sexp)

    let string_of_sexp = function
      | `Atom s -> s
      | sexp ->
          failwith
            (Format.asprintf "Instead of an atom, got: %a" CCSexp.pp sexp)
  end
end
