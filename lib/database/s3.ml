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

(* Helper to clean endpoint URL *)
let clean_endpoint url =
  let url = if String.ends_with ~suffix:"/" url then
    String.sub url 0 (String.length url - 1)
  else url in
  if String.starts_with ~prefix:"https://" url then
    String.sub url 8 (String.length url - 8)
  else if String.starts_with ~prefix:"http://" url then
    String.sub url 7 (String.length url - 7)
  else url

(* S3 client configuration from environment variables *)
let key_id = match Sys.getenv_opt "B2_ACCESS_KEY" with 
  | Some v -> v 
  | None -> Printf.printf "[ERROR] B2_ACCESS_KEY not set\n"; ""

let app_key = match Sys.getenv_opt "B2_SECRET_KEY" with
  | Some v -> v
  | None -> Printf.printf "[ERROR] B2_SECRET_KEY not set\n"; ""

let endpoint = 
  match Sys.getenv_opt "B2_ENDPOINT" with
  | Some v -> clean_endpoint v
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

(* AWS Signature V4 helpers *)
let hmac_sha256 ~key message =
  Digestif.SHA256.hmac_string ~key message |> Digestif.SHA256.to_hex

let get_date_stamp () =
  let tm = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d%02d%02d" 
    (tm.tm_year + 1900)
    (tm.tm_mon + 1)
    tm.tm_mday

let get_amz_date () =
  let tm = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d%02d%02dT%02d%02d%02dZ"
    (tm.tm_year + 1900)
    (tm.tm_mon + 1)
    tm.tm_mday
    tm.tm_hour
    tm.tm_min
    tm.tm_sec

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
    Error (Configuration_error "B2_ACCESS_KEY not set")
  else if String.length app_key = 0 then
    Error (Configuration_error "B2_SECRET_KEY not set")
  else if String.length endpoint = 0 then
    Error (Configuration_error "B2_ENDPOINT not set")
  else if String.length bucket = 0 then
    Error (Configuration_error "B2_BUCKET_NAME not set")
  else if String.length region = 0 then
    Error (Configuration_error "B2_REGION not set")
  else
    Ok ()

(* Create AWS Signature v4 authorization *)
let make_authorization ~content_type ~content_length ~object_key =
  let amz_date = get_amz_date () in
  let date_stamp = get_date_stamp () in
  
  (* Task 1: Create canonical request *)
  let canonical_uri = Printf.sprintf "/%s/%s" bucket object_key in
  let canonical_querystring = "" in
  let canonical_headers = Printf.sprintf
    "content-length:%d\ncontent-type:%s\nhost:%s\nx-amz-date:%s\n"
    content_length
    content_type
    endpoint
    amz_date
  in
  let signed_headers = "content-length;content-type;host;x-amz-date" in
  let payload_hash = Digestif.SHA256.digest_string "" |> Digestif.SHA256.to_hex in
  let canonical_request = Printf.sprintf
    "PUT\n%s\n%s\n%s\n%s\n%s"
    canonical_uri
    canonical_querystring
    canonical_headers
    signed_headers
    payload_hash
  in
  
  (* Task 2: Create string to sign *)
  let algorithm = "AWS4-HMAC-SHA256" in
  let credential_scope = Printf.sprintf
    "%s/%s/s3/aws4_request"
    date_stamp
    region
  in
  let string_to_sign = Printf.sprintf
    "%s\n%s\n%s\n%s"
    algorithm
    amz_date
    credential_scope
    (Digestif.SHA256.digest_string canonical_request |> Digestif.SHA256.to_hex)
  in
  
  (* Task 3: Calculate signature *)
  let k_date = hmac_sha256 ~key:("AWS4" ^ app_key) date_stamp in
  let k_region = hmac_sha256 ~key:k_date region in
  let k_service = hmac_sha256 ~key:k_region "s3" in
  let k_signing = hmac_sha256 ~key:k_service "aws4_request" in
  let signature = hmac_sha256 ~key:k_signing string_to_sign in
  
  (* Task 4: Create authorization header *)
  let authorization = Printf.sprintf
    "%s Credential=%s/%s, SignedHeaders=%s, Signature=%s"
    algorithm
    key_id
    credential_scope
    signed_headers
    signature
  in
  
  (* Return headers *)
  [
    ("Authorization", authorization);
    ("x-amz-date", amz_date);
    ("Content-Type", content_type);
    ("Content-Length", string_of_int content_length);
  ]

(* Exponential backoff helper *)
let rec retry_with_backoff ~attempt ~max_attempts ~f =
  if attempt > max_attempts then
    f ()
  else
    try%lwt
      f ()
    with _ ->
      let wait_time = float_of_int (1 lsl attempt) in (* exponential backoff *)
      let%lwt () = Lwt_unix.sleep wait_time in
      retry_with_backoff ~attempt:(attempt + 1) ~max_attempts ~f

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
          let content_length = String.length contents in
          let content_type = "application/octet-stream" in
          let headers = Header.of_list (
            make_authorization 
              ~content_type 
              ~content_length
              ~object_key
          ) in
          
          let upload_attempt () =
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
              | 408 -> (* Request timeout *)
                  Lwt.fail (Failure "Retryable error: HTTP 408 Request Timeout")
              | status when status >= 500 && status <= 599 ->
                  (* Server errors *)
                  Lwt.fail (Failure (Printf.sprintf "Retryable error: HTTP %d" status))
              | _ ->
                  let* error_body = Cohttp_lwt.Body.to_string body in
                  Lwt.return (Error (Upload_failed (status, error_body)))
            with e ->
              Lwt.fail e (* Let retry logic handle the error *)
          in
          
          try%lwt
            retry_with_backoff ~attempt:0 ~max_attempts:3 ~f:upload_attempt
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