open Cmdliner
open Lwt.Syntax

(* Import required modules *)
module Scanner = Photocaml.Scanner  (* For scanning directories for photos *)
module Database = Database (* Database operations *)

(* Logging functions for better debugging *)
let log_debug msg = Printf.printf "[DEBUG] %s\n%!" msg
let log_info msg = Printf.printf "[INFO] %s\n%!" msg
let log_warn msg = Printf.printf "[WARN] %s\n%!" msg
let log_error msg = Printf.eprintf "[ERROR] %s\n%!" msg

(* Initialize database and return a result *)
let init_database () =
  let* result = Database.init () in
  match result with
  | Ok () -> Lwt.return_ok ()
  | Error err -> Lwt.return_error err

(* Command to list all albums *)
let list_albums db =
  Database.Cli.list_albums db

(* Command to upload photos to an album *)
let upload_photos ~db ~album_id ~files =
  Database.Cli.upload_photos ~db ~album_id ~files

(* Command line interface setup *)
let list_cmd =
  let doc = "List all albums" in
  let info = Cmd.info "list" ~doc in
  Cmd.v info Term.(const (fun () -> 
    Lwt_main.run (
      let* init_result = init_database () in
      match init_result with
      | Error _ -> Lwt.return 1
      | Ok () ->
          let* result = Database.with_connection list_albums in
          match result with
          | Error _ ->
              let* () = Database.cleanup () in
              Lwt.return 1
          | Ok albums ->
              List.iter (fun (album : Database.Db.album) ->
                Printf.printf "Album: %s (ID: %s)\n  Created: %s\n\n"
                  album.name album.id 
                  (Ptime.to_rfc3339 ~space:true album.created_at)
              ) albums;
              let* () = Database.cleanup () in
              Lwt.return 0
    )) $ const ())

let upload_cmd =
  let doc = "Upload photos to an album" in
  let album_id =
    let doc = "Album ID to upload to" in
    Arg.(required & pos 0 (some string) None & info [] ~docv:"ALBUM_ID" ~doc)
  in
  let dir =
    let doc = "Directory containing photos" in
    Arg.(required & pos 1 (some string) None & info [] ~docv:"DIRECTORY" ~doc)
  in
  let info = Cmd.info "upload" ~doc in
  Cmd.v info Term.(const (fun id dir () -> 
    Lwt_main.run (
      let* init_result = init_database () in
      match init_result with
      | Error _ -> Lwt.return 1
      | Ok () ->
          let* files = Lwt_unix.files_of_directory dir 
            |> Lwt_stream.to_list 
            |> Lwt.map (List.filter (fun f -> f <> "." && f <> ".."))
            |> Lwt.map (List.map (Filename.concat dir))
          in
          let* result = Database.with_connection (fun db ->
            upload_photos ~db ~album_id:id ~files
          ) in
          match result with
          | Error _ ->
              let* () = Database.cleanup () in
              Lwt.return 1
          | Ok count ->
              let* () = Database.cleanup () in
              Lwt.return 0
    )) $ album_id $ dir $ const ())

(* Default command group combining all subcommands *)
let default_cmd =
  let doc = "PhotoCaml CLI tool for managing photo albums" in
  let info = Cmd.info "photocaml-cli" ~version:"0.1.0" ~doc in
  Cmd.group info [list_cmd; upload_cmd]

(* Program entry point *)
let () = exit (Cmd.eval' default_cmd) 