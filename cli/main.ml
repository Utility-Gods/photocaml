(* PhotoCaml CLI tool - Interactive Version
   This module implements an interactive command-line interface for PhotoCaml.
   It uses:
   - Cmdliner for basic CLI setup: https://erratique.ch/software/cmdliner
   - ANSITerminal for colored output: https://github.com/Chris00/ANSITerminal
   - Lwt for async operations: https://ocsigen.org/lwt/latest/manual
*)

(* Open required modules *)
open Cmdliner  (* For basic CLI setup: https://erratique.ch/software/cmdliner *)
open Lwt.Syntax  (* For let* syntax in async code: https://ocsigen.org/lwt/latest/manual#_the_syntax_module *)
open ANSITerminal

(* Helper functions for interactive UI *)

(* Print a styled message with optional newline
   Example: print_styled [Bold; Foreground Blue] "Hello" true *)
let print_styled styles msg newline =
  if newline then
    let () = 
      ANSITerminal.printf styles "%s\n" msg;
      flush stdout
    in
    Lwt.return_unit
  else
    let () = 
      ANSITerminal.printf styles "%s" msg;
      flush stdout
    in
    Lwt.return_unit

(* Print a header with a title
   Example: print_header "Welcome to PhotoCaml" *)
let print_header title =
  let* () = print_styled [ANSITerminal.Bold; ANSITerminal.Foreground Blue] "\n=== PhotoCaml Interactive CLI ===" true in
  let* () = print_styled [ANSITerminal.Bold] (Printf.sprintf "\n%s\n" title) true in
  Lwt.return_unit

(* Print a success message
   Example: print_success "Upload complete!" *)
let print_success msg =
  print_styled [ANSITerminal.Bold; ANSITerminal.Foreground Green] (Printf.sprintf "✓ %s" msg) true

(* Print an error message
   Example: print_error "Failed to connect" *)
let print_error msg =
  print_styled [ANSITerminal.Bold; ANSITerminal.Foreground Red] (Printf.sprintf "✗ Error: %s" msg) true

(* Print a progress message
   Example: print_progress "Uploading..." *)
let print_progress msg =
  print_styled [ANSITerminal.Bold; ANSITerminal.Foreground Yellow] (Printf.sprintf "⋯ %s" msg) true

(* Interactive prompt for user input
   Parameters:
   - prompt: string - The prompt message
   - default: string option - Optional default value
   Returns: string Lwt.t - User's input
   Example: let* answer = prompt "Enter your name" None *)
let rec prompt ?(default=None) msg =
  let default_str = match default with
    | Some d -> Printf.sprintf " [%s]" d
    | None -> ""
  in
  let* () = print_styled [ANSITerminal.Bold] (Printf.sprintf "%s%s: " msg default_str) false in
  let* input = Lwt_io.read_line Lwt_io.stdin in
  match input, default with
  | "", Some d -> Lwt.return d
  | "", None -> prompt ~default msg  (* Retry if empty and no default *)
  | input, _ -> Lwt.return input

(* Interactive menu for selecting from a list of options
   Parameters:
   - title: string - Menu title
   - options: string list - List of options
   Returns: int Lwt.t - Selected index
   Example: let* choice = select_menu "Choose an action" ["Upload"; "List"; "Exit"] *)
let select_menu title options =
  let rec print_options idx = function
    | [] -> Lwt.return_unit
    | opt :: rest ->
        let* () = print_styled [ANSITerminal.Bold] (Printf.sprintf "%d) %s\n" (idx + 1) opt) true in
        print_options (idx + 1) rest
  in
  let rec get_choice () =
    let* input = prompt ~default:None "Enter your choice (number)" in
    try
      let n = int_of_string input in
      if n >= 1 && n <= List.length options then
        Lwt.return (n - 1)
      else
        let* () = print_error "Invalid choice" in
        get_choice ()
    with Failure _ ->
      let* () = print_error "Please enter a number" in
      get_choice ()
  in
  let* () = print_header title in
  let* () = print_options 0 options in
  get_choice ()

(* Command implementations *)

(* Interactive album listing
   Shows albums in a paginated list with options to view details
   Returns: (unit, string) result Lwt.t *)
let list_albums verbose =
  let* () = print_header "Available Albums" in
  let* () = 
    if verbose then
      print_progress "Fetching albums (verbose mode)..."
    else
      print_progress "Fetching albums..."
  in
  (* TODO: Implement actual album fetching *)
  let dummy_albums = [
    "Vacation 2024";
    "Family Photos";
    "Work Events"
  ] in
  
  let* () = Lwt_list.iter_s
    (fun album ->
      let* () = print_styled [ANSITerminal.Bold] (Printf.sprintf "• %s\n" album) true in
      Lwt.return_unit)
    dummy_albums
  in
  
  let* choice = select_menu "Album Actions" [
    "View Details";
    "Back to Main Menu"
  ] in
  
  match choice with
  | 0 -> (* View Details *)
      let* album = prompt ~default:None "Enter album name" in
      let* () = print_progress (Printf.sprintf "Fetching details for %s..." album) in
      (* TODO: Implement album details fetch *)
      let* () = print_success "Details fetched successfully" in
      Lwt.return_ok ()
  | _ -> Lwt.return_ok ()

(* Interactive photo upload
   Guides user through selecting an album and files to upload
   Parameters:
   - album_id: string option - Optional pre-selected album ID
   - paths: string list - Optional pre-selected paths
   - verbose: bool - Whether to show detailed output
   Returns: (unit, string) result Lwt.t *)
let rec upload album_id paths verbose =
  let* () = print_header "Photo Upload" in
  
  (* Get album ID interactively if not provided *)
  let* final_album_id = match album_id with
    | Some id -> Lwt.return id
    | None ->
        let* () = print_progress "Loading available albums..." in
        (* TODO: Fetch actual albums *)
        let dummy_albums = ["abc123"; "def456"; "ghi789"] in
        let* choice = select_menu "Select Target Album" dummy_albums in
        Lwt.return (List.nth dummy_albums choice)
  in
  
  (* Get paths interactively if not provided *)
  let* final_paths = match paths with
    | [] ->
        let* path = prompt ~default:None "Enter path to photo or directory" in
        Lwt.return [path]
    | ps -> Lwt.return ps
  in
  
  (* Process uploads with progress indication *)
  let* () = print_progress (Printf.sprintf "Uploading to album %s..." final_album_id) in
  let total = List.length final_paths in
  let* () = 
    Lwt_list.iteri_s
      (fun idx path -> 
        let* () = print_progress (Printf.sprintf "[%d/%d] Processing: %s" (idx + 1) total path) in
        if verbose then
          let* () = print_styled [ANSITerminal.Bold] (Printf.sprintf "  Checking file: %s\n" path) true in
          let* () = Lwt_unix.sleep 0.5 in (* Simulate processing *)
          let* () = print_styled [ANSITerminal.Bold] "  Uploading...\n" true in
          Lwt.return_unit
        else
          Lwt.return_unit)
      final_paths
  in
  
  (* TODO: Implement actual upload *)
  let* () = print_success "Upload completed successfully!" in
  
  (* Ask for next action *)
  let* choice = select_menu "What would you like to do next?" [
    "Upload more photos";
    "View uploaded photos";
    "Back to main menu"
  ] in
  
  match choice with
  | 0 -> upload None [] verbose
  | 1 -> list_albums verbose
  | _ -> Lwt.return_ok ()

(* Interactive main menu - core of the application *)
let run_interactive verbose =
  let rec main_loop () =
    let* () = print_styled [Bold; Foreground Blue] "\nWelcome to PhotoCaml!" true in
    let* () = 
      if verbose then
        print_styled [Bold; Foreground Blue] "Starting in verbose mode..." true
      else
        Lwt.return_unit
    in
    let* choice = select_menu "Main Menu" [
      "List Albums";
      "Upload Photos";
      "Exit"
    ] in
    match choice with
    | 0 -> 
        let* result = list_albums verbose in
        (match result with
        | Ok () -> main_loop ()
        | Error msg -> 
            let* () = print_error msg in
            main_loop ())
    | 1 ->
        let* result = upload None [] verbose in
        (match result with
        | Ok () -> main_loop ()
        | Error msg -> 
            let* () = print_error msg in
            main_loop ())
    | _ -> Lwt.return_unit
  in
  (* Initialize terminal *)
  let () = 
    ANSITerminal.erase Screen;
    ANSITerminal.set_cursor 1 1;
    flush stdout
  in
  match Lwt_main.run (main_loop ()) with
  | () -> `Ok ()

(* Simplified CLI setup - just the verbose flag *)
let verbose_flag =
  let doc = "Give more detailed output" in
  Arg.(value & flag & info ["v"; "verbose"] ~doc)

(* Main program setup *)
let main =
  let doc = "An interactive photo album management tool" in
  let man = [
    `S Manpage.s_description;
    `P "PhotoCaml is an interactive tool for managing your photo albums.";
    `P "Use the arrow keys and enter to navigate the menus.";
    `S Manpage.s_examples;
    `P "Run with -v or --verbose for detailed output:";
    `P "  $(tname) --verbose";
  ] in
  let info = Cmd.info "photocaml-cli" ~version:"0.1.0" ~doc ~man in
  Cmd.v info Term.(ret (const run_interactive $ verbose_flag))

(* Program entry point *)
let () = exit @@ Cmd.eval main 