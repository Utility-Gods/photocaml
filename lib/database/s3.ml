open Lwt.Infix

(* S3 client configuration from environment variables *)
let key_id = try Sys.getenv "B2_KEY_ID" with Not_found -> ""
let app_key = try Sys.getenv "B2_APP_KEY" with Not_found -> ""
let endpoint = try Sys.getenv "B2_ENDPOINT" with Not_found -> ""
let bucket = try Sys.getenv "B2_BUCKET_NAME" with Not_found -> ""

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
  album_id ^ "/" ^ unique_filename
  
(* Gets a public URL for a key (path) *)
let get_public_url key =
  endpoint ^ bucket ^ "/" ^ key

(* In a real implementation, this would upload to S3
   For now, we'll simulate by storing locally *)
let upload_file ~album_id ~file_path ~filename =
  let key = prepare_path ~album_id filename in
  let public_url = get_public_url key in
  
  (* Create the local uploads directory if needed *)
  let base_dir = "./static/uploads" in
  let () = 
    if not (Sys.file_exists base_dir) then
      Sys.mkdir base_dir 0o755 
  in
  
  (* Create unique directory for album if not exists *)
  let album_dir = Filename.concat base_dir album_id in
  let () = 
    if not (Sys.file_exists album_dir) then
      Sys.mkdir album_dir 0o755 
  in
  
  (* Local file where we'll store the copy *)
  let local_filename = Filename.basename key in
  let local_path = Filename.concat album_dir local_filename in
  
  (* Copy the file to "simulate" S3 upload *)
  try%lwt
    Lwt_io.with_file ~mode:Lwt_io.Input file_path (fun in_ch ->
      Lwt_io.with_file ~mode:Lwt_io.Output local_path (fun out_ch ->
        let%lwt content = Lwt_io.read in_ch in
        Lwt_io.write out_ch content
      )
    ) >>= fun () ->
    
    (* Log that we're simulating the upload *)
    Lwt_io.printl ("Simulating S3 upload to: " ^ public_url) >>= fun () ->
    Lwt.return (Ok public_url)
  with e ->
    Lwt.return (Error (Printexc.to_string e))