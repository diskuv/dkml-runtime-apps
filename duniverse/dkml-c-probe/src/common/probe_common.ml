(******************************************************************************)
(*  Copyright 2022 Diskuv, Inc.                                               *)
(*                                                                            *)
(*  Licensed under the Apache License, Version 2.0 (the "License");           *)
(*  you may not use this file except in compliance with the License.          *)
(*  You may obtain a copy of the License at                                   *)
(*                                                                            *)
(*      http://www.apache.org/licenses/LICENSE-2.0                            *)
(*                                                                            *)
(*  Unless required by applicable law or agreed to in writing, software       *)
(*  distributed under the License is distributed on an "AS IS" BASIS,         *)
(*  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  *)
(*  See the License for the specific language governing permissions and       *)
(*  limitations under the License.                                            *)
(******************************************************************************)

(** [dos2unix s] converts all CRLF sequences in [s] into LF. Assumes [s] is ASCII encoded. *)
let dos2unix s =
  let l = String.length s in
  String.to_seqi s
  (* Shrink [\r\n] into [\n] *)
  |> Seq.filter_map (function
       | i, '\r' when i + 1 < l && s.[i + 1] == '\n' -> None
       | _, c -> Some c)
  |> String.of_seq

(** [normalize_into_upper_alnum s] translates the ASCII string [s] into only
    the letters and numbers; lowercase letters are converted into uppercase,
    and any non alphanumeric character is translated into an underscore. *)
let normalize_into_upper_alnum =
  String.map (function
    | c when (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') -> c
    | c when c >= 'a' && c <= 'z' -> Char.uppercase_ascii c
    | _ -> '_')
