open Lwt.Syntax

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
  (* Debug HMAC *)
  let result = Digestif.SHA256.hmac_string ~key message |> Digestif.SHA256.to_hex in
  Printf.printf "[DEBUG] HMAC: key=%s, message=%s, result=%s\n" 
    (if String.length key > 20 then String.sub key 0 20 ^ "..." else key)
    (if String.length message > 20 then String.sub message 0 20 ^ "..." else message)
    result;
  result

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
  let unique_filename = album_id ^ "_" ^ timestamp ^ "_" ^ safe_filename in
  
  (* Return simple filename for the root of the bucket *)
  unique_filename

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
let make_authorization ~http_method ~content_type ~object_key ~contents =
  let amz_date = get_amz_date () in
  let date_stamp = get_date_stamp () in
  
  (* Calculate content hash *)
  let payload_hash = 
    Digestif.SHA256.digest_string contents |> Digestif.SHA256.to_hex
  in
  
  (* Task 1: Create canonical request *)
  let canonical_uri = Printf.sprintf "/%s/%s" bucket object_key in
  let canonical_querystring = "" in
  
  (* Format canonical_headers exactly as required *)
  let canonical_headers = Printf.sprintf
    "content-type:%s\nhost:%s\nx-amz-content-sha256:%s\nx-amz-date:%s\n"
    content_type
    endpoint
    payload_hash
    amz_date
  in
  let signed_headers = "content-type;host;x-amz-content-sha256;x-amz-date" in
  
  let canonical_request = Printf.sprintf
    "%s\n%s\n%s\n%s\n%s\n%s"
    http_method
    canonical_uri
    canonical_querystring
    canonical_headers
    signed_headers
    payload_hash
  in
  
  Printf.printf "[DEBUG] Canonical request:\n%s\n" canonical_request;
  
  (* Task 2: Create string to sign *)
  let algorithm = "AWS4-HMAC-SHA256" in
  let credential_scope = Printf.sprintf
    "%s/%s/s3/aws4_request"
    date_stamp
    region
  in
  let canonical_request_hash = Digestif.SHA256.digest_string canonical_request |> Digestif.SHA256.to_hex in
  
  let string_to_sign = Printf.sprintf
    "%s\n%s\n%s\n%s"
    algorithm
    amz_date
    credential_scope
    canonical_request_hash
  in
  
  Printf.printf "[DEBUG] String to sign:\n%s\n" string_to_sign;
  
  (* Task 3: Calculate signature *)
  let k_secret = "AWS4" ^ app_key in
  let k_date = 
    Digestif.SHA256.hmac_string ~key:k_secret date_stamp 
    |> Digestif.SHA256.to_raw_string
  in
  let k_region = 
    Digestif.SHA256.hmac_string ~key:k_date region
    |> Digestif.SHA256.to_raw_string
  in
  let k_service = 
    Digestif.SHA256.hmac_string ~key:k_region "s3"
    |> Digestif.SHA256.to_raw_string
  in
  let k_signing = 
    Digestif.SHA256.hmac_string ~key:k_service "aws4_request"
    |> Digestif.SHA256.to_raw_string
  in
  let signature = 
    Digestif.SHA256.hmac_string ~key:k_signing string_to_sign
    |> Digestif.SHA256.to_hex
  in
  
  (* Task 4: Create authorization header *)
  let credential = Printf.sprintf "%s/%s/%s/s3/aws4_request" 
    key_id date_stamp region in
    
  let authorization = Printf.sprintf
    "%s Credential=%s,SignedHeaders=%s,Signature=%s"
    algorithm
    credential
    signed_headers
    signature
  in
  
  Printf.printf "[DEBUG] Authorization: %s\n" authorization;
  
  (* Return headers *)
  [
    ("Authorization", authorization);
    ("x-amz-date", amz_date);
    ("x-amz-content-sha256", payload_hash);
    ("Content-Type", content_type);
    ("Content-Length", string_of_int (String.length contents));
    ("Host", endpoint);
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
      let uri_string = Printf.sprintf "https://%s/%s/%s" endpoint bucket object_key in
      
      Printf.printf "[DEBUG] Uploading to: %s\n" uri_string;
      
      (* Read file contents as binary *)
      let* file_contents = 
        try%lwt
          Printf.printf "[DEBUG] Reading file: %s\n" file_path;
          let%lwt fd = Lwt_unix.openfile file_path [Unix.O_RDONLY] 0o644 in
          let%lwt stats = Lwt_unix.fstat fd in
          let file_size = stats.st_size in
          let buffer = Bytes.create file_size in
          let%lwt read_bytes = Lwt_unix.read fd buffer 0 file_size in
          let%lwt () = Lwt_unix.close fd in
          
          if read_bytes <> file_size then
            Lwt.return (Error (Internal_error (Printf.sprintf "Failed to read entire file: %d/%d bytes" read_bytes file_size)))
          else begin
            Printf.printf "[DEBUG] Successfully read %d bytes\n" read_bytes;
            let contents = Bytes.to_string buffer in
            Lwt.return (Ok contents)
          end
        with e -> 
          Lwt.return (Error (Internal_error (Printf.sprintf "Failed to read file: %s" (Printexc.to_string e))))
      in
      
      match file_contents with
      | Error e -> Lwt.return (Error e)
      | Ok contents ->
          let upload_attempt () =
            try%lwt
              let uri = Uri.of_string uri_string in
              
              (* Create headers with AWS Signature V4 *)
              let content_type = "application/octet-stream" in
              let headers = make_authorization
                ~http_method:"PUT"
                ~content_type
                ~object_key
                ~contents
              in
              
              (* Convert headers list to Cohttp.Header.t *)
              let headers = List.fold_left (fun h (name, value) ->
                Cohttp.Header.add h name value
              ) (Cohttp.Header.init ()) headers in
              
              (* Create body *)
              let body = Cohttp_lwt.Body.of_string contents in
              
              (* Make request *)
              let* (resp, body) = Cohttp_lwt_unix.Client.put ~headers ~body uri in
              let status = Cohttp.Response.status resp in
              let status_code = Cohttp.Code.code_of_status status in
              
              (* Read response body *)
              let* body_str = Cohttp_lwt.Body.to_string body in
              
              Printf.printf "[DEBUG] Response status: %d\n" status_code;
              Printf.printf "[DEBUG] Response body: %s\n" body_str;
              
              if status_code >= 200 && status_code < 300 then begin
                let url = get_public_url object_key in
                Printf.printf "[DEBUG] Success! Uploaded to: %s\n" url;
                Lwt.return (Ok url)
              end else begin
                Printf.printf "[DEBUG] Upload failed with status: %d\n" status_code;
                Lwt.return (Error (Upload_failed (status_code, body_str)))
              end
            with e ->
              Lwt.fail e
          in
          
          try%lwt
            retry_with_backoff ~attempt:0 ~max_attempts:3 ~f:upload_attempt
          with e ->
            Lwt.return (Error (Network_error (Printexc.to_string e)))

let upload_data ~album_id ~data ~filename =
  (* Create a temporary file *)
  let temp_file = Filename.temp_file "b2_upload" ".tmp" in
  
  try%lwt
    (* Write the data to the temp file in binary mode *)
    let fd = Unix.openfile temp_file [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o644 in
    let bytes_written = Unix.write fd (Bytes.of_string data) 0 (String.length data) in
    Unix.close fd;
    
    Printf.printf "[DEBUG] Written %d bytes to temporary file %s\n" bytes_written temp_file;
    
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
