(* Import the S3 module which handles cloud storage operations *)
module S3 = S3

(* Re-export Db module functions *)
let init = Db.init
let cleanup = Db.cleanup
let with_connection = Db.with_connection

let get_connection = Db.get_connection

let get_db_url = Db.get_db_url

(* Define a Database module to encapsulate all database operations *)

module Db = struct
  (* Define the album record type
     Learn more about OCaml records: https://ocaml.org/docs/records
     Example:
     let my_album = {
       id = "123";
       name = "Vacation 2024";
       description = Some "Summer trip";
       cover_image = None;
       slug = "vacation-2024";
       created_at = current_time;
     } *)

   type album = {
    id : string;              (* Unique identifier for the album *)
    name : string;            (* Album name *)
    description : string option; (* Optional description. None if not provided *)
    cover_image : string option; (* Optional path to cover image *)
    slug : string;            (* URL-friendly version of name (e.g., "my-album") *)
    created_at : Ptime.t;     (* Timestamp when album was created *)
  }

  type photo = {
    id : string;            (* Unique identifier for the photo *)
    album_id : string;      (* Foreign key referencing the album *)
    filename : string;      (* Original filename *)
    bucket_path : string;   (* Path in S3 bucket *)
    width : int option;     (* Optional image width in pixels *)
    height : int option;    (* Optional image height in pixels *)
    size_bytes : int option;  (* Optional file size in bytes *)
    uploaded_at : Ptime.t;  (* Timestamp when photo was uploaded *)
  }


  (* Inner module for related types *)
  module T = struct
    (* Photo record type
       Example:
       let my_photo = {
         id = "456";
         album_id = "123";
         filename = "beach.jpg";
         bucket_path = "photos/123/beach.jpg";
         width = Some 1920;
         height = Some 1080;
         size_bytes = Some 1024000;
         uploaded_at = current_time;
       } *)
  

    (* Share record type for album sharing functionality
       Example:
       let my_share = {
         id = "789";
         album_id = "123";
         share_token = "abc123";
         is_public = true;
         expires_at = Some expiry_date;
         created_at = current_time;
       } *)
   

    (* Photo paths for different sizes of the same photo
       Example:
       let paths = {
         original = "photos/123/beach.jpg";
         thumbnail = "photos/123/beach_thumbnail.jpg";
         medium = "photos/123/beach_medium.jpg";
       } *)
    type photo_paths = {
      original : string;      (* Path to original size image *)
      thumbnail : string;     (* Path to thumbnail size *)
      medium : string;        (* Path to medium size *)
    }
    
  end

  type share = {
    id : string;            (* Unique identifier for the share *)
    album_id : string;      (* Foreign key referencing the album *)
    share_token : string;   (* Unique token for accessing shared album *)
    is_public : bool;       (* Whether the share is public *)
    expires_at : Ptime.t option; (* Optional expiration date *)
    created_at : Ptime.t;   (* When the share was created *)
  }
  
  (* Database operations using ppx_rapper for type-safe SQL
     Learn more: https://github.com/roddyyaga/ppx_rapper *)

  (* Create a new album
     Usage: create_album ~id:"123" ~name:"Vacation" ~description:(Some "Trip") ~cover_image:None ~slug:"vacation" db *)
  let create_album =
    [%rapper
      execute
        {sql|
          INSERT INTO albums (id, name, description, cover_image, slug)
          VALUES (%string{id}, %string{name}, %string?{description}, %string?{cover_image}, %string{slug})
        |sql}]

  (* Get a single album by ID
     Usage: get_album ~id:"123" db *)
  let get_album =
    [%rapper
      get_one
        {sql|
          SELECT @string{id}, @string{name}, @string?{description}, @string?{cover_image}, @string{slug}, @ptime{created_at}
          FROM albums WHERE id = %string{id}
        |sql}
        record_out]

  (* Add a new photo to an album
     Usage: add_photo ~id:"456" ~album_id:"123" ~filename:"beach.jpg" ~bucket_path:"..." db *)
  let add_photo =
    [%rapper
      execute
        {sql|
          INSERT INTO photos (id, album_id, filename, bucket_path, width, height, size_bytes)
          VALUES (%string{id}, %string{album_id}, %string{filename}, %string{bucket_path}, %int?{width}, %int?{height}, %int?{size_bytes})
        |sql}]

  (* Get all photos in an album
     Usage: get_photos_by_album ~album_id:"123" db *)
  let get_photos_by_album =
    [%rapper
      get_many
        {sql|
          SELECT @string{id}, @string{album_id}, @string{filename}, @string{bucket_path}, @int?{width}, @int?{height}, @int?{size_bytes}, @ptime{uploaded_at}
          FROM photos WHERE album_id = %string{album_id} ORDER BY uploaded_at DESC
        |sql}
        record_out]

  (* Create a new share for an album
     Usage: create_share ~id:"789" ~album_id:"123" ~share_token:"abc123" ~is_public:true ~expires_at:None db *)
  let create_share =
    [%rapper
      execute
        {sql|
          INSERT INTO shares (id, album_id, share_token, is_public, expires_at)
          VALUES (%string{id}, %string{album_id}, %string{share_token}, %bool{is_public}, %ptime?{expires_at})
        |sql}]

  (* Get all albums ordered by creation date
     Usage: get_all_albums db *)
  let get_all_albums =
    [%rapper
      get_many
        {sql| SELECT @string{id}, @string{name}, @string?{description}, @string?{cover_image}, @string{slug}, @ptime{created_at}
        FROM albums ORDER BY created_at DESC
        |sql}
        record_out]
    ()

  (* Generate paths for different sizes of a photo
     Usage: 
     let photo = get_photo ...
     let paths = make_photo_paths photo *)
  let make_photo_paths (photo : photo) : T.photo_paths =
    let ext = Filename.extension photo.filename in
    let album_folder = photo.album_id in
    let base = Filename.remove_extension photo.bucket_path in
    {
      original = Filename.concat album_folder photo.bucket_path;
      thumbnail = Filename.concat album_folder (base ^ "_thumbnail" ^ ext);
      medium = Filename.concat album_folder (base ^ "_medium" ^ ext);
    }

  (* Get album_id by share token for public share route *)
  let get_album_id_by_share_token db token =
    let open Lwt.Syntax in
    let query =
      [%rapper
        get_opt
          {sql|
            SELECT @string{id}, @string{album_id}, @string{share_token}, @bool{is_public}, @ptime?{expires_at}, @ptime{created_at}
            FROM shares
            WHERE share_token = %string{token}
              AND is_public = TRUE
              AND (expires_at IS NULL OR expires_at > NOW())
          |sql}
          record_out
      ]
    in
    let* result = query ~token db in
    match result with
    | Ok (Some share) -> Lwt.return_some share.album_id
    | Ok None -> Lwt.return_none
    | Error _ -> Lwt.return_none

  (* Generate a unique ID for database records
     Usage: let new_id = generate_id () *)
  let generate_id () =
    (* Create 16 bytes for UUID *)
    let random_bytes = Bytes.create 16 in
    (* Fill with random values *)
    for i = 0 to 15 do
      Bytes.set random_bytes i (Char.chr (Random.int 256))
    done;
    (* Convert each byte to hex *)
    let hex_of_char c =
      let code = Char.code c in
      let hi = code lsr 4 in (* Get high 4 bits *)
      let lo = code land 0xf in (* Get low 4 bits *)
      let to_hex n = if n < 10 then Char.chr (n + 48) else Char.chr (n + 87) in
      (to_hex hi, to_hex lo)
    in
    (* Create string buffer for result *)
    let buffer = Buffer.create 32 in
    (* Convert bytes to hex string with dashes *)
    for i = 0 to 15 do
      let hi, lo = hex_of_char (Bytes.get random_bytes i) in
      Buffer.add_char buffer hi;
      Buffer.add_char buffer lo;
      if i = 3 || i = 5 || i = 7 || i = 9 then Buffer.add_char buffer '-'
    done;
    Buffer.contents buffer

  (* Delete an album by ID
     Usage: delete_album ~id:"123" db *)
  let delete_album =
    [%rapper
      execute
        {sql|
          DELETE FROM albums WHERE id = %string{id}
        |sql}]
  end

(* CLI-specific functions that handle error types appropriately *)
module Cli = struct
  open Lwt.Syntax
  
  (* Expose create_share for CLI use *)
  let create_share = Db.create_share

  (* Log functions for CLI operations *)
  let log_error msg = Printf.eprintf "[ERROR] %s\n%!" msg
  let log_info msg = Printf.printf "[INFO] %s\n%!" msg

  (* Upload photos to an album, handling both S3 and database errors *)


  

  let upload_photos ~db ~album_id ~files =
    (* Track successful uploads *)
    let successes = ref 0 in
    
    (* Process each file *)
    let process_file file =
      let open Lwt.Infix in
      let filename = Filename.basename file in
      let ext = Filename.extension filename in
      let name_wo_ext =
        if String.length ext > 0 then
          String.sub filename 0 (String.length filename - String.length ext)
        else filename
      in
      let medium_file = Filename.temp_file ~temp_dir:"docs" (name_wo_ext ^ "_medium") ext in
      let thumb_file = Filename.temp_file ~temp_dir:"docs" (name_wo_ext ^ "_thumbnail") ext in
      
      let run_convert src dest size =
        let cmd = Printf.sprintf "convert '%s' -resize '%s' '%s'" src size dest in
        Lwt_process.exec ("/bin/sh", [| "/bin/sh"; "-c"; cmd |]) >|= function
        | Unix.WEXITED 0 -> Ok ()
        | _ -> Error (Printf.sprintf "convert failed: %s" cmd)
      in
      
      let* medium_res = run_convert file medium_file "1024x1024>" in
      (match medium_res with
      | Ok () -> log_info ("Generated medium image: " ^ medium_file)
      | Error e -> log_error e);
      let* thumb_res = run_convert file thumb_file "256x256>" in
      (match thumb_res with
      | Ok () -> log_info ("Generated thumbnail image: " ^ thumb_file)
      | Error e -> log_error e);
      
      (* Upload original *)
      let* s3_result = S3.upload_file ~album_id ~file_path:file ~filename in
      match s3_result with
      | Error e -> 
          log_error (Printf.sprintf "S3 upload failed for %s: %s" file (S3.string_of_upload_error e));
          Lwt.return_ok ()
      | Ok url ->
          let id = Db.generate_id () in
          let* db_result = Db.add_photo ~id ~album_id
            ~filename
            ~bucket_path:url
            ~width:None
            ~height:None
            ~size_bytes:None
            db
          in
          let*_ =
            match db_result with
            | Ok _ ->
                incr successes;
                log_info (Printf.sprintf "Successfully uploaded %s" file);
                Lwt.return_ok ()
            | Error e ->
                log_error (Printf.sprintf "Database error for %s: %s" file (Caqti_error.show e));
                Lwt.return_ok ()
          in
      
      (* Upload medium *)
      let medium_filename = name_wo_ext ^ "_medium" ^ ext in
      let* _ =
        if Sys.file_exists medium_file then
          S3.upload_file ~album_id ~file_path:medium_file ~filename:medium_filename >|= function
          | Ok _ -> log_info ("Uploaded medium image: " ^ medium_filename)
          | Error e -> log_error ("Failed to upload medium image: " ^ S3.string_of_upload_error e)
        else Lwt.return_unit
      in
      (* Upload thumbnail *)
      let thumb_filename = name_wo_ext ^ "_thumbnail" ^ ext in
      let* _ =
        if Sys.file_exists thumb_file then
          S3.upload_file ~album_id ~file_path:thumb_file ~filename:thumb_filename >|= function
          | Ok _ -> log_info ("Uploaded thumbnail image: " ^ thumb_filename)
          | Error e -> log_error ("Failed to upload thumbnail image: " ^ S3.string_of_upload_error e)
        else Lwt.return_unit
      in
      (* Clean up temp files *)
      (try Sys.remove medium_file with _ -> ());
      (try Sys.remove thumb_file with _ -> ());
      Lwt.return_ok ()

    in
    
    (* Process all files *)
    let* results = Lwt_list.map_s process_file files in
    if List.exists Result.is_error results then
      (* Use Caqti_error.request_failed to construct the error *)
      let msg = Caqti_error.Msg "Some files failed to upload" in
      Lwt.return_error (Caqti_error.request_failed 
        ~uri:(Uri.of_string "") 
        ~query:"upload_photos" 
        msg)
    else
      Lwt.return_ok !successes

  (* List all albums with proper error handling for CLI *)
  let list_albums db =
    let* result = Db.get_all_albums db in
    match result with
    | Ok albums -> Lwt.return_ok albums
    | Error e -> 
        log_error (Printf.sprintf "Failed to list albums: %s" (Caqti_error.show e));
        Lwt.return_error e
end