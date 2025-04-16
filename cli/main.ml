(* PhotoCaml CLI tool
   For more information about cmdliner: https://erratique.ch/software/cmdliner/doc/Cmdliner 
   
   This module implements a command-line interface for PhotoCaml using the Cmdliner library.
   Cmdliner helps in creating beautiful and complete command line interfaces.
*)

(* Open required modules *)
open Cmdliner  (* For building CLI interfaces: https://erratique.ch/software/cmdliner *)
open Lwt.Syntax  (* For let* syntax in async code: https://ocsigen.org/lwt/latest/manual/manual#_the_syntax_module *)

(* Command implementations *)

(* List all available albums 
   Returns: (unit, string) result Lwt.t - An asynchronous result
   Example usage from shell: photocaml-cli albums *)
let list_albums verbose =
  let* () = 
    if verbose then
      Lwt_io.printl "Verbose mode: Starting album fetch operation..."
    else
      Lwt_io.printl "Fetching albums..."
  in
  (* TODO: Implement album listing using Database module *)
  Lwt.return_ok ()

(* Upload photos to an album 
   Parameters:
   - album_id: string - The ID of the target album
   - paths: string list - List of file paths to upload
   - verbose: bool - Whether to show detailed output
   Returns: (unit, string) result Lwt.t
   Example usage from shell: photocaml-cli upload abc123 photo1.jpg photo2.jpg *)
let upload album_id paths verbose =
  let* () = 
    if verbose then
      Lwt_io.printlf "Verbose mode: Starting upload to album %s with %d files..." album_id (List.length paths)
    else
      Lwt_io.printlf "Uploading to album %s..." album_id 
  in
  let* () = 
    Lwt_list.iter_s
      (fun path -> 
        let* () = Lwt_io.printlf "  Processing: %s" path in
        if verbose then
          Lwt_io.printlf "    Verbose: Checking file type and permissions for %s" path
        else
          Lwt.return_unit)
      paths
  in
  (* TODO: Implement photo upload using Database module *)
  Lwt.return_ok ()

(* CLI interface *)

(* Common options record type
   Fields:
   - verbose: bool - Whether to show detailed output
   See: https://erratique.ch/software/cmdliner/doc/Cmdliner.Arg.html *)
type common_opts = {
  verbose : bool;
}

(* Command implementations that convert Lwt results to exit codes *)
let handle_albums common_opts =
  match Lwt_main.run (list_albums common_opts.verbose) with
  | Ok () -> Ok ()
  | Error msg ->
      Printf.eprintf "Error: %s\n" msg;
      Error msg

let handle_upload common_opts album_id paths =
  match Lwt_main.run (upload album_id paths common_opts.verbose) with
  | Ok () -> Ok ()
  | Error msg ->
      Printf.eprintf "Error: %s\n" msg;
      Error msg

(* Command line interface construction *)

(* Define common command line options
   See: https://erratique.ch/software/cmdliner/doc/Cmdliner.Arg.html *)
let common_opts =
  let docs = Manpage.s_common_options in
  let verbose =
    let doc = "Give more detailed output" in
    Arg.(value & flag & info ["v"; "verbose"] ~docs ~doc)
  in
  Term.(const (fun verbose -> { verbose }) $ verbose)

(* The albums command
   Creates a command that lists all available albums
   See: https://erratique.ch/software/cmdliner/doc/Cmdliner.Cmd.html *)
let albums_cmd =
  let doc = "List all available albums" in
  let man = [
    `S Manpage.s_description;
    `P "List all available albums in the system.";
  ] in
  let info = Cmd.info "albums" ~doc ~man in
  Cmd.v info Term.(const handle_albums $ common_opts)

(* The upload command
   Creates a command that uploads photos to an album
   See: https://erratique.ch/software/cmdliner/doc/Cmdliner.Cmd.html *)
let upload_cmd =
  let doc = "Upload photos to an album" in
  let man = [
    `S Manpage.s_description;
    `P "Upload one or more photos to a specified album.";
    `P "$(tname) ALBUM_ID [PATH...]";
    `P "Example: $(tname) abc123 photo1.jpg photo2.jpg ./vacation-pics/";
  ] in
  let album_id =
    let doc = "ID of the album to upload to" in
    Arg.(required & pos 0 (some string) None & info [] ~docv:"ALBUM_ID" ~doc)
  in
  let paths =
    let doc = "Paths to photos or directories containing photos" in
    Arg.(non_empty & pos_right 0 string [] & info [] ~docv:"PATHS" ~doc)
  in
  let info = Cmd.info "upload" ~doc ~man in
  Cmd.v info Term.(const handle_upload $ common_opts $ album_id $ paths)

(* Main entry point 
   Combines all commands into a single CLI program
   See: https://erratique.ch/software/cmdliner/doc/Cmdliner.Cmd.html *)
let main =
  let doc = "A minimal CLI tool for uploading photos to albums" in
  let man = [
    `S Manpage.s_description;
    `P "$(tname) is a command line tool for managing photo albums.";
    `S Manpage.s_commands;
    `S Manpage.s_bugs;
    `P "Report bugs to your issue tracker.";
  ] in
  let info = Cmd.info "photocaml-cli" ~version:"0.1.0" ~doc ~man in
  (* Default behavior when no command is specified - show help *)
  let default = Term.(ret (const (fun () -> `Help (`Pager, None)) $ const ())) in
  Cmd.group ~default info [albums_cmd; upload_cmd]

(* Program entry point
   Evaluates the main command and exits with appropriate status code *)
let () = exit @@ Cmd.eval_result main 