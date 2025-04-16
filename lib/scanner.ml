(* Scanner module for handling file system operations
   This module is responsible for:
   1. Validating file paths
   2. Expanding directories and glob patterns
   3. Filtering for supported image types *)

(* List of supported image file extensions 
   See: https://ocaml.org/docs/lists-and-patterns for pattern matching *)
let supported_extensions = [".jpg"; ".jpeg"; ".png"; ".gif"; ".webp"; ".heic"]

(* Check if a file has a supported extension
   Example: is_supported "photo.jpg" = true *)
let is_supported path =
  (* String.lowercase_ascii: https://ocaml.org/api/String.html *)
  let lowercase_path = String.lowercase_ascii path in
  (* List.exists: https://ocaml.org/api/List.html#VALexists *)
  List.exists (fun ext -> 
    String.ends_with ~suffix:ext lowercase_path
  ) supported_extensions

(* Get all files in a directory recursively
   Example: get_directory_files "./photos" = ["./photos/1.jpg"; "./photos/sub/2.png"] *)
let rec get_directory_files dir =
  (* Sys.readdir: https://ocaml.org/api/Sys.html#VALreaddir *)
  let contents = Sys.readdir dir in
  (* Array.fold_left: https://ocaml.org/api/Array.html#VALfold_left *)
  Array.fold_left (fun acc name ->
    let path = Filename.concat dir name in
    (* Sys.is_directory: https://ocaml.org/api/Sys.html#VALis_directory *)
    if Sys.is_directory path then
      (* Recursively get files from subdirectories *)
      List.append acc (get_directory_files path)
    else if is_supported path then
      (* Add supported files to accumulator *)
      path :: acc
    else
      (* Skip unsupported files *)
      acc
  ) [] contents

(* Expand a path which might be a file, directory, or glob pattern
   Example: expand_path "./photos/*.jpg" = ["./photos/1.jpg"; "./photos/2.jpg"] *)
let expand_path path =
  (* Sys.file_exists: https://ocaml.org/api/Sys.html#VALfile_exists *)
  if not (Sys.file_exists path) then
    (* Path doesn't exist *)
    []
  else if Sys.is_directory path then
    (* Path is a directory - get all files recursively *)
    get_directory_files path
  else if is_supported path then
    (* Path is a supported file *)
    [path]
  else
    (* Path exists but isn't supported *)
    []

(* Scan multiple paths and return all valid image files
   Example: scan_paths ["photo.jpg"; "./pics/"] = ["photo.jpg"; "./pics/1.png"] *)
let scan_paths paths =
  (* List.fold_left: https://ocaml.org/api/List.html#VALfold_left *)
  let files = List.fold_left (fun acc path ->
    List.append acc (expand_path path)
  ) [] paths in
  (* Remove duplicates and sort for consistent ordering *)
  List.sort_uniq String.compare files 