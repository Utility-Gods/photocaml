(* PhotoCaml CLI - Main Interface Module *)

(* Import required modules *)
open Cmdliner     (* Command line argument parsing - see https://erratique.ch/software/cmdliner *)
open Lwt.Syntax   (* Provides let* syntax for async operations - see https://ocsigen.org/lwt/latest/manual/manual *)

(* Module aliases for better readability *)
module Scanner = Photocaml.Scanner  (* For scanning directories for photos *)
module Database = Database          (* Database operations module *)

(* Logging utilities for better debugging and user feedback 
   Printf.printf: Format and print strings - see https://ocaml.org/api/Printf.html
   %s: string placeholder
   %!: flush output buffer immediately *)
let log_debug msg = Printf.printf "[DEBUG] %s\n%!" msg
let log_info msg = Printf.printf "[INFO] %s\n%!" msg
let log_warn msg = Printf.printf "[WARN] %s\n%!" msg
let log_error msg = Printf.eprintf "[ERROR] %s\n%!" msg  (* eprintf writes to stderr *)

(* Initialize database connection pool
   Returns: ('a, 'b) result Lwt.t - An asynchronous result type
   Example: 
   match%lwt init_database () with
   | Ok () -> handle_success ()
   | Error err -> handle_error err *)
let init_database () =
  let* result = Database.init () in  (* let* is for handling Lwt promises *)
  match result with
  | Ok () -> Lwt.return_ok ()        (* Return successful initialization *)
  | Error err -> Lwt.return_error err (* Return error if initialization fails *)

(* Command to list all albums in the database
   Takes a database connection and returns a list of albums *)
let list_albums db =
  Database.Cli.list_albums db

(* Command to upload photos to an album
   Parameters:
   - db: Database connection
   - album_id: Target album's UUID
   - files: List of file paths to upload *)
let upload_photos ~db ~album_id ~files =
  Database.Cli.upload_photos ~db ~album_id ~files

(* Interactive menu display function
   Prints the available options with emoji for better UX *)
let print_menu () =
  Printf.printf "\n📷 PhotoCaml CLI Menu\n";
  Printf.printf "==================\n";
  Printf.printf "1. List all albums\n";
  Printf.printf "2. Upload photos to album\n";
  Printf.printf "3. Generate sharable album link\n";
  Printf.printf "4. Exit\n";
  Printf.printf "\nEnter your choice (1-4): %!"

(* Get and validate directory path from user input
   Uses recursion to keep asking until a valid path is provided
   Example: let photo_dir = get_directory_path () *)
let rec get_directory_path () =
  Printf.printf "Enter the directory path containing photos: %!";
  let dir = read_line () in  (* Read user input - see https://ocaml.org/api/Stdlib.html#VALread_line *)
  if Sys.file_exists dir && Sys.is_directory dir then
    dir  (* Return valid directory path *)
  else begin
    Printf.printf "\nError: Invalid directory path. Please try again.\n";
    get_directory_path ()  (* Recursively ask for valid input *)
  end

(* Get album ID from user input
   Simple input function that returns the entered string *)
let select_album_interactive db =
  let open Lwt.Syntax in
  let* albums_result = Database.Cli.list_albums db in
  match albums_result with
  | Error _ ->
      Printf.printf "Failed to fetch albums.\n%!";
      Lwt.return_none
  | Ok albums ->
      if albums = [] then (Printf.printf "No albums found.\n"; Lwt.return_none)
      else (
        Printf.printf "\nSelect an album:\n";
        List.iteri (fun i (album : Database.Db.album) ->
          Printf.printf "%d. %s (ID: %s)\n" (i+1) album.name album.id
        ) albums;
        Printf.printf "Enter album number: %!";
        match int_of_string_opt (read_line ()) with
        | Some n when n > 0 && n <= List.length albums ->
            Lwt.return_some (List.nth albums (n-1)).id
        | _ -> Printf.printf "Invalid selection.\n"; Lwt.return_none
      )


(* Handle the list albums command
   Uses Lwt_main.run to execute async operations in synchronous context
   Returns: int (0 for success, 1 for failure) *)
let handle_list_albums () =
  Lwt_main.run (
    let* init_result = init_database () in
    match init_result with
    | Error _ -> 
        log_error "Failed to initialize database";
        Lwt.return 1
    | Ok () ->
        (* Use database connection to list albums *)
        let* result = Database.with_connection list_albums in
        match result with
        | Error _ ->
            let* () = Database.cleanup () in
            log_error "Failed to list albums";
            Lwt.return 1
        | Ok albums ->
            (* Pretty print album information *)
            Printf.printf "\nAvailable Albums:\n";
            Printf.printf "================\n";
            List.iter (fun (album : Database.Db.album) ->
              Printf.printf "Album: %s\nID: %s\nCreated: %s\n\n"
                album.name album.id 
                (Ptime.to_rfc3339 ~space:true album.created_at)
            ) albums;
            let* () = Database.cleanup () in
            Lwt.return 0
  )

(* Handle photo upload command
   Parameters:
   - album_id: Target album's UUID
   - dir: Directory containing photos to upload
   Returns: int (0 for success, 1 for failure) *)
let handle_upload_photos_interactive () =
  Lwt_main.run (
    let* init_result = init_database () in
    match init_result with
    | Error _ -> 
        log_error "Failed to initialize database";
        Lwt.return 1
    | Ok () ->
        let* result = Database.with_connection (fun db ->
          let* album_id_opt = select_album_interactive db in
          match album_id_opt with
          | None ->
              let msg = Caqti_error.Msg "No album selected" in
              Lwt.return_error (Caqti_error.request_failed ~uri:(Uri.of_string "") ~query:"upload_photos" msg)
          | Some album_id ->
              let dir = get_directory_path () in
              let* files = Lwt_unix.files_of_directory dir 
                |> Lwt_stream.to_list 
                |> Lwt.map (List.filter (fun f -> f <> "." && f <> ".."))
                |> Lwt.map (List.map (Filename.concat dir))
              in
              upload_photos ~db ~album_id ~files
        ) in
        match result with
        | Error _ ->
            let* () = Database.cleanup () in
            log_error "Failed to upload photos";
            Lwt.return 1
        | Ok count ->
            let* () = Database.cleanup () in
            log_info (Printf.sprintf "Successfully uploaded %d photos" count);
            Lwt.return 0
  )


(* Interactive menu loop
   Handles user input and dispatches to appropriate handlers
   Returns: int (0 for success) *)
let handle_generate_share_link () =
  Lwt_main.run (
    let* init_result = init_database () in
    match init_result with
    | Error _ -> log_error "Failed to initialize database"; Lwt.return 1
    | Ok () ->
        let* result = Database.with_connection (fun db ->
          let* album_id_opt = select_album_interactive db in
          match album_id_opt with
          | None ->
              let msg = Caqti_error.Msg "No album selected" in
              Lwt.return_error (Caqti_error.request_failed ~uri:(Uri.of_string "") ~query:"create_share" msg)
          | Some album_id ->
              let share_id = Database.Db.generate_id () in
              let share_token = Database.Db.generate_id () in
              let is_public = true in
              let expires_at = None in
              let* share_result = Database.Cli.create_share ~id:share_id ~album_id ~share_token ~is_public ~expires_at db in
              match share_result with
              | Ok () ->
                  let domain = "https://yourdomain.com" in
                  Printf.printf "Sharable link: %s/share/%s\n" domain share_token;
                  Lwt.return_ok ()
              | Error _ ->
                  log_error "Failed to create share link";
                  let msg = Caqti_error.Msg "Failed to create share link" in
                  Lwt.return_error (Caqti_error.request_failed ~uri:(Uri.of_string "") ~query:"create_share" msg)
        ) in
        let* () = Database.cleanup () in
        match result with
        | Ok _ -> Lwt.return 0
        | Error _ -> Lwt.return 1
  )

let interactive_menu () =
  let rec menu_loop () =
    print_menu ();
    match read_line () with
    | "1" -> 
        let _ = handle_list_albums () in
        menu_loop ()
    | "2" -> 
        let _ = handle_upload_photos_interactive () in
        menu_loop ()
    | "3" ->
        let _ = handle_generate_share_link () in
        menu_loop ()
    | "4" -> 
        Printf.printf "\nGoodbye! 👋\n";
        0
    | _ -> 
        Printf.printf "\nInvalid choice. Please try again.\n";
        menu_loop ()
  in
  menu_loop ()

(* Command line interface setup using Cmdliner
   See: https://erratique.ch/software/cmdliner/doc/Cmdliner *)

(* List command - shows all albums *)
let list_cmd =
  let doc = "List all albums" in
  let info = Cmd.info "list" ~doc in
  Cmd.v info Term.(const (fun () -> handle_list_albums ()) $ const ())

(* Upload command - uploads photos to an album *)
let upload_cmd =
  let doc = "Upload photos to an album" in
  let info = Cmd.info "upload" ~doc in
  Cmd.v info Term.(const (fun () -> handle_upload_photos_interactive ()) $ const ())

(* Interactive menu command *)
let interactive_cmd =
  let doc = "Start interactive menu mode" in
  let info = Cmd.info "menu" ~doc in
  Cmd.v info Term.(const (fun () -> interactive_menu ()) $ const ())

(* Default command group combining all subcommands *)
let default_cmd =
  let doc = "PhotoCaml CLI tool for managing photo albums" in
  let info = Cmd.info "photocaml-cli" ~version:"0.1.0" ~doc in
  Cmd.group info [list_cmd; upload_cmd; interactive_cmd]

(* Program entry point
   Evaluates the command line interface and exits with the returned status code *)
let () = exit (Cmd.eval' default_cmd) 