open Lwt.Syntax
open Cohttp
open Cohttp_lwt_unix

type upload_error = 
  | Configuration_error of string
  | Network_error of string
  | Upload_failed of int * string
  | Internal_error of string

let string_of_upload_error = function
  | Configuration_error msg -> Printf.sprintf "Configuration error: %s" msg
  | Network_error msg -> Printf.sprintf "Network error: %s" msg
  | Upload_failed (code, msg) -> Printf.sprintf "Upload failed (HTTP %d): %s" code msg
  | Internal_error msg -> Printf.sprintf "Internal error: %s" msg

(* Initialize dotenv *)
let () = 
  (* Load environment variables from .env file *)
  Dotenv.export ~debug:true ();
  Printf.printf "[DEBUG] Attempted to load .env file\n";
  Printf.printf "[DEBUG] Current working directory: %s\n" (Sys.getcwd ())

(* S3 client configuration from environment variables *)
let key_id = match Sys.getenv_opt "B2_KEY_ID" with 
  | Some v -> v 
  | None -> Printf.printf "[ERROR] B2_KEY_ID not set\n"; ""

let app_key = match Sys.getenv_opt "B2_APP_KEY" with
  | Some v -> v
  | None -> Printf.printf "[ERROR] B2_APP_KEY not set\n"; ""

let endpoint = 
  match Sys.getenv_opt "B2_ENDPOINT" with
  | Some v -> 
      (* Remove any trailing slash from endpoint *)
      let v = if String.ends_with ~suffix:"/" v then
        String.sub v 0 (String.length v - 1)
      else v in
      v
  | None -> Printf.printf "[ERROR] B2_ENDPOINT not set\n"; ""

let bucket = match Sys.getenv_opt "B2_BUCKET_NAME" with
  | Some v -> v
  | None -> Printf.printf "[ERROR] B2_BUCKET_NAME not set\n"; ""

let region = match Sys.getenv_opt "B2_REGION" with
  | Some v -> v
  | None -> Printf.printf "[ERROR] B2_REGION not set\n"; ""

(* Add debug logging *)
let () = 
  Printf.printf "[DEBUG] S3 Config:\n";
  Printf.printf "  Endpoint: '%s'\n" endpoint;
  Printf.printf "  Bucket: '%s'\n" bucket;
  Printf.printf "  Region: '%s'\n" region;
  Printf.printf "  Key ID length: %d\n" (String.length key_id);
  Printf.printf "  App Key length: %d\n" (String.length app_key)

(* Function to prepare paths for storage *)
let prepare_path ~album_id filename =
  (* Generate a unique filename *)
  let timestamp = Int.to_string (int_of_float (Unix.time ())) in
  let safe_filename = 
    Filename.basename filename
    |> String.map (fun c -> if c = ' ' then '_' else c)
  in
  let unique_filename = timestamp ^ "_" ^ safe_filename in
  
  (* Return full path as it would be in S3 bucket *)
  Printf.sprintf "albums/%s/%s" album_id unique_filename

(* Gets a public URL for a key (path) *)
let get_public_url key =
  Printf.sprintf "https://%s/%s/%s" endpoint bucket key

(* Validate configuration before making requests *)
let validate_config () =
  if String.length key_id = 0 then 
    Error (Configuration_error "B2_KEY_ID not set")
  else if String.length app_key = 0 then
    Error (Configuration_error "B2_APP_KEY not set")
  else if String.length endpoint = 0 then
    Error (Configuration_error "B2_ENDPOINT not set")
  else if String.length bucket = 0 then
    Error (Configuration_error "B2_BUCKET_NAME not set")
  else if String.length region = 0 then
    Error (Configuration_error "B2_REGION not set")
  else
    Ok ()

(* Helper to create authorization header *)
let make_auth_header () =
  let auth = Base64.encode_string (key_id ^ ":" ^ app_key) in
  ("Authorization", "Basic " ^ auth)

(* Upload file using cohttp *)
let upload_file ~album_id ~file_path ~filename =
  match validate_config () with
  | Error e -> Lwt.return (Error e)
  | Ok () ->
      let object_key = prepare_path ~album_id filename in
      let uri = Uri.make 
        ~scheme:"https"
        ~host:endpoint
        ~path:(Printf.sprintf "/%s/%s" bucket object_key)
        ()
      in
      
      Printf.printf "[DEBUG] Uploading to: %s\n" (Uri.to_string uri);
      
      (* Read file contents *)
      let* file_contents = 
        try%lwt
          let* contents = Lwt_io.with_file ~mode:Lwt_io.Input file_path Lwt_io.read in
          Lwt.return (Ok contents)
        with e -> 
          Lwt.return (Error (Internal_error (Printf.sprintf "Failed to read file: %s" (Printexc.to_string e))))
      in
      
      match file_contents with
      | Error e -> Lwt.return (Error e)
      | Ok contents ->
          let headers = Header.of_list [
            make_auth_header ();
            ("Content-Type", "application/octet-stream");
            ("Content-Length", string_of_int (String.length contents));
          ] in
          
          try%lwt
            let* (response, body) = Client.put 
              ~headers
              ~body:(Cohttp_lwt.Body.of_string contents)
              uri 
            in
            
            let status = Response.status response |> Code.code_of_status in
            match status with
            | 200 | 201 -> 
                let url = get_public_url object_key in
                Lwt.return (Ok url)
            | _ ->
                let* error_body = Cohttp_lwt.Body.to_string body in
                Lwt.return (Error (Upload_failed (status, error_body)))
          with e ->
            Lwt.return (Error (Network_error (Printexc.to_string e)))

let upload_data ~album_id ~data ~filename =
  (* Create a temporary file *)
  let temp_file = Filename.temp_file "b2_upload" ".tmp" in
  
  try%lwt
    (* Write the data to the temp file *)
    let%lwt () = Lwt_io.with_file ~mode:Lwt_io.Output temp_file
      (fun channel -> Lwt_io.write channel data) in
    
    (* Upload the temp file *)
    let%lwt result = upload_file ~album_id ~file_path:temp_file ~filename in
    
    (* Clean up temp file *)
    let%lwt () = Lwt_unix.unlink temp_file in
    
    Lwt.return result
  with exn ->
    (* Clean up temp file in case of error *)
    let%lwt () = 
      try%lwt Lwt_unix.unlink temp_file
      with _ -> Lwt.return_unit 
    in
    Lwt.return (Error (Internal_error (Printexc.to_string exn)))