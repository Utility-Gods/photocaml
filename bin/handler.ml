open Types

let debug fmt = Printf.ksprintf (fun s -> Printf.printf "[DEBUG] %s\n%!" s) fmt
let info fmt = Printf.ksprintf (fun s -> Printf.printf "[INFO] %s\n%!" s) fmt

(* Extract S3 key from a full S3 URL *)
let s3_key_of_url url =
  try
    let uri = Uri.of_string url in
    match Uri.path uri with
    | "" -> url
    | path when String.length path > 0 && path.[0] = '/' -> String.sub path 1 (String.length path - 1)
    | path -> path
  with _ -> url

(* Utility to get _thumbnail or _medium variant of a filename or path *)
let append_variant_to_filename filename variant =
  let ext = Filename.extension filename in
  let base = Filename.remove_extension filename in
  base ^ "_" ^ variant ^ ext

let warn fmt = Printf.ksprintf (fun s -> Printf.printf "[WARN] %s\n%!" s) fmt
let error fmt = Printf.ksprintf (fun s -> Printf.printf "[ERROR] %s\n%!" s) fmt


let home_handler _ =
  let content = Home.render () in
  Layout.render
    ~title:"Home"
    ~content
    |> Dream.html

let album_list_handler req =
  try%lwt
    let%lwt albums_with_photos = Dream.sql req (fun db ->
      let%lwt result = Database.Db.get_all_albums db in
      match result with
      | Ok albums -> 
          (* For each album, get its photos *)
          let%lwt albums_with_photos = Lwt_list.map_s (fun (album : Database.Db.album) ->
            let%lwt photos_result = Database.Db.get_photos_by_album ~album_id:album.Database.Db.id db in
            match photos_result with
            | Ok photos -> Lwt.return (album, photos)
            | Error e -> 
                Dream.log "Failed to get photos for album %s: %s" album.Database.Db.id (Caqti_error.show e);
                Lwt.return (album, [])
          ) albums in
          Lwt.return albums_with_photos
      | Error e -> Lwt.fail (Failure (Caqti_error.show e))
    ) in
    debug "Found %d albums" (List.length albums_with_photos);
    let content = Album.render ~albums:albums_with_photos ~request:req in
    Layout.render
      ~title:"Albums"
      ~content
    |> Dream.html
  with exn ->
    error "Exception in album listing: %s" (Printexc.to_string exn);
    Dream.html ~status:`Internal_Server_Error "Error loading albums"

let new_album_page_handler _ =
  let content = New_album.render () in
  Layout.render
    ~title:"Create New Album"
    ~content
    |> Dream.html

let album_detail_handler req =
  let album_id = Dream.param req "id" in
  (try%lwt
    let%lwt album = Dream.sql req (fun db ->
        let%lwt result = Database.Db.get_album ~id:album_id db in
        match result with
        | Ok album_record -> Lwt.return album_record
        | Error e -> Lwt.fail (Failure (Caqti_error.show e))
      )
    in
    let%lwt photos = Dream.sql req (fun db ->
        let%lwt result = Database.Db.get_photos_by_album ~album_id:album_id db in
        match result with
        | Ok photos -> Lwt.return photos
        | Error e -> Lwt.fail (Failure (Caqti_error.show e))
      )
    in
    let content = Album_detail.render ~album ~photos in
    Layout.render
      ~title:("Album: " ^ album.name)
      ~content
      |> Dream.html
  with Failure msg ->
    Dream.log "Failed to get album %s: %s" album_id msg;
    Dream.html ~status:`Internal_Server_Error ("Failed to retrieve album: " ^ msg)
  )

let upload_page_handler req =
  let album_id = Dream.param req "id" in
  (try%lwt
    let%lwt album = Dream.sql req (fun db ->
        let%lwt result = Database.Db.get_album ~id:album_id db in
        match result with
        | Ok album_record -> Lwt.return album_record
        | Error e -> Lwt.fail (Failure (Caqti_error.show e))
      )
    in
    let content = Upload.render ~album ~request:req in
    Layout.render
      ~title:"Upload Photos"
      ~content
      |> Dream.html
  with Failure msg ->
    Dream.log "Failed to get album %s for upload: %s" album_id msg;
    Dream.html ~status:`Internal_Server_Error ("Failed to access album: " ^ msg)
  )

let delete_album_handler req =
  let album_id = Dream.param req "id" in
  try%lwt
    let%lwt result = Dream.sql req (fun db ->
      Database.Db.delete_album ~id:album_id db
    ) in
    match result with
    | Ok () -> 
        Dream.html ~status:`OK {|<div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded" role="alert" hx-swap-oob="true" id="notification">Album deleted successfully</div>|}
    | Error e -> 
        Dream.html ~status:`Internal_Server_Error {|<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded" role="alert" hx-swap-oob="true" id="notification">Failed to delete album</div>|}
  with exn ->
    Dream.html ~status:`Internal_Server_Error {|<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded" role="alert" hx-swap-oob="true" id="notification">Error deleting album</div>|}

let share_album_handler req =
  let token = Dream.param req "token" in
  let open Lwt.Syntax in
  let* share_result = Dream.sql req (fun db ->
    let open Lwt.Syntax in
    let* album_id_opt = Database.Db.get_album_id_by_share_token db token in
    match album_id_opt with
    | Some album_id ->
        let* album_result = Database.Db.get_album ~id:album_id db in
        let* photos_result = Database.Db.get_photos_by_album ~album_id db in
        (match album_result, photos_result with
        | Ok album, Ok photos -> Lwt.return_some (album, photos)
        | _ -> Lwt.return_none)
    | None -> Lwt.return_none
  ) in
  match share_result with
  | Some (album, photos) ->
      let photo_variants = List.map (fun (photo : Database.Db.photo) ->
        let album_id = photo.Database.Db.album_id in
        let filename = photo.Database.Db.filename in
        let original_key = Filename.concat album_id filename in
        let medium_key = Filename.concat album_id (append_variant_to_filename filename "medium") in
        let thumbnail_key = Filename.concat album_id (append_variant_to_filename filename "thumbnail") in
        let placeholder = "/static/img/placeholder.jpg" in
        let build_url key =
          match Database.S3.get_signed_url ~key ~expires_in:3600 with
          | Ok url -> url
          | Error _ -> placeholder
        in
        let medium_url =
          let url = build_url medium_key in
          if url = placeholder then build_url original_key else url
        in
        {
          thumbnail_url = build_url thumbnail_key;
          medium_url = medium_url;
          original_url = build_url original_key;
          filename = photo.Database.Db.filename;
        }
      ) photos in
      (* Print photo_variants to CLI for debugging *)
      let string_of_photo_variant v =
        Printf.sprintf "{ thumbnail_url = %s; medium_url = %s; original_url = %s; filename = %s }"
          v.thumbnail_url v.medium_url v.original_url v.filename
      in
      Printf.printf "[DEBUG] photo_variants:\n";
      List.iter (fun v -> Printf.printf "[DEBUG]   %s\n" (string_of_photo_variant v)) photo_variants;
      let content = Share_album.render ~album ~photos:photo_variants in
      Layout.render
        ~title:("Shared Album: " ^ album.name)
        ~content
      |> Dream.html
  | None ->
      Dream.html ~status:`Not_Found "<h2>Invalid or expired share link</h2>"

let share_photos_api_handler req =
  let open Lwt.Syntax in
  match Dream.query req "token", Dream.query req "offset", Dream.query req "limit" with
  | Some token, Some offset_str, Some limit_str ->
      let offset = int_of_string_opt offset_str |> Option.value ~default:0 in
      let limit = int_of_string_opt limit_str |> Option.value ~default:5 in
      let* result = Dream.sql req (fun db ->
        let open Lwt.Syntax in
        let* album_id_opt = Database.Db.get_album_id_by_share_token db token in
        match album_id_opt with
        | Some album_id ->
            let* photos_result = Database.Db.get_photos_by_album_paginated ~album_id ~offset ~limit db in
            (match photos_result with
            | Ok photos -> Lwt.return_some (album_id, photos)
            | _ -> Lwt.return_none)
        | None -> Lwt.return_none
      ) in
      (match result with
      | Some (album_id, photos) ->
          let photo_variants = List.map (fun (photo : Database.Db.photo) ->
            let filename = photo.Database.Db.filename in
            let original_key = Filename.concat album_id filename in
            let medium_key = Filename.concat album_id (append_variant_to_filename filename "medium") in
            let thumbnail_key = Filename.concat album_id (append_variant_to_filename filename "thumbnail") in
            let placeholder = "/static/img/placeholder.jpg" in
            let build_url key =
              match Database.S3.get_signed_url ~key ~expires_in:3600 with
              | Ok url -> url
              | Error _ -> placeholder
            in
            let medium_url =
              let url = build_url medium_key in
              if url = placeholder then build_url original_key else url
            in
            {
              thumbnail_url = build_url thumbnail_key;
              medium_url = medium_url;
              original_url = build_url original_key;
              filename = photo.Database.Db.filename;
            }
          ) photos in
          let json =
            `List (
              List.map (fun v ->
                `Assoc [
                  ("thumbnail_url", `String v.thumbnail_url);
                  ("medium_url", `String v.medium_url);
                  ("original_url", `String v.original_url);
                  ("filename", `String v.filename)
                ]
              ) photo_variants
            )
          in
          Dream.json (Yojson.Safe.to_string json)
      | None -> Dream.json ~status:`Not_Found "[]")
  | _ -> Dream.json ~status:`Bad_Request "[]"

(* === End Route Handlers Section === *)



  let generate_slug name =
    let name_lower = String.lowercase_ascii name in
    let replace_spaces = 
      let parts = String.split_on_char ' ' name_lower in
      String.concat "-" parts
    in
    (* Filter out non-alphanumeric characters *)
    let buffer = Buffer.create (String.length replace_spaces) in
    String.iter (fun c ->
      if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' then
        Buffer.add_char buffer c
    ) replace_spaces;
    Buffer.contents buffer

  
  let create_album_handler req =
    debug "Processing album creation form";
    
    (* Manually parse form data instead of using Dream.form to avoid CSRF check *)
    let%lwt body = Dream.body req in
    debug "Raw form body: %s" body;
    
    (* Parse form data manually *)
    let params = 
      body 
      |> String.split_on_char '&' 
      |> List.filter_map (fun param ->
          match String.split_on_char '=' param with
          | [key; value] -> 
              let decoded_key = Uri.pct_decode key in
              let decoded_value = Uri.pct_decode (String.map (fun c -> if c = '+' then ' ' else c) value) in
              debug "Param: %s = %s" decoded_key decoded_value;
              Some (decoded_key, decoded_value)
          | _ -> None
        )
    in
    
    debug "Parsed %d form parameters" (List.length params);
    
    (* Extract parameters *)
    let name = 
      try List.assoc "name" params
      with Not_found -> 
        error "Name field missing from form data";
        Dream.log "Name field missing from form data";
        ""
    in
    
    (* Validate name is not empty *)
    if String.trim name = "" then (
      error "Album name is required";
      Dream.html ~status:`Bad_Request "Album name is required"
    ) else (
      let description = List.assoc_opt "description" params in
      let slug = generate_slug name in
      
     
      try%lwt
        (* Dream.sql expects callback returning 'a Lwt.t, raising exception on error *) 
        let%lwt () = Dream.sql req (fun db ->
          debug "Creating album in database: %s" name;
          Dream.log "Creating album: %s" name;
          let%lwt result = Database.Db.create_album ~name ~description ~cover_image:None ~slug db in
          match result with
          | Ok () -> 
              debug "Album created successfully";
              Lwt.return_unit
          | Error e -> 
              let err_msg = Caqti_error.show e in
              error "Database error: %s" err_msg;
              Dream.log "Database error: %s" err_msg;
              Lwt.fail (Failure err_msg)
        ) in
        debug "Redirecting to /album";
        Dream.redirect req "/album"
      with Failure msg ->
        error "Failed to create album: %s" msg;
        Dream.log "Failed to create album: %s" msg;
        Dream.html ~status:`Internal_Server_Error ("Failed to create album: " ^ msg)
    )
        
  let upload_photo_handler req =
    let album_id = Dream.param req "id" in
    
    (* First, verify the album exists *)
    try%lwt
      let%lwt album = Dream.sql req (fun db ->
        let%lwt result = Database.Db.get_album ~id:album_id db in
        match result with
        | Ok album_record -> Lwt.return album_record
        | Error e -> Lwt.fail (Failure (Caqti_error.show e))
      ) in
      
      (* Create a temporary directory for file processing *)
      let temp_dir = Filename.concat (Filename.get_temp_dir_name ()) "photocaml_uploads" in
      let () = 
        if not (Sys.file_exists temp_dir) then
          Sys.mkdir temp_dir 0o755
      in
      
      (* Handle file upload *)
      match%lwt Dream.multipart req with
      | `Ok parts ->
          (* Process each file in the multipart form *)
          let photo_entries = 
            match List.assoc_opt "photos" parts with
            | Some entries -> entries
            | None -> []
          in
          
          (* Track if any files were successfully uploaded *)
          let uploaded = ref false in
          
          (* Process uploads - in Dream, entries are (string option * string) pairs *)
          let%lwt () = Lwt_list.iter_s (fun (filename_opt, file_data) ->
            (* Use the filename from the multipart form if available *)
            let original_filename = 
              match filename_opt with 
              | Some name -> name
              | None -> "uploaded_file.jpg"
            in
            
            (* Use only the sanitized original filename for S3 and DB; do NOT add timestamp *)
            let safe_filename = 
              Filename.basename original_filename
              |> String.map (fun c -> if c = ' ' then '_' else c)
            in
            (* S3 key: album_id/original_filename *)
            let s3_key = Filename.concat album_id safe_filename in
            
            (* Save to temp file first *)
            let temp_path = Filename.concat temp_dir safe_filename in
            
            (* Generate unique ID for the database *)
            
            try%lwt
              (* Write file to temporary location *)
              let%lwt () = Lwt_io.with_file ~mode:Lwt_io.Output temp_path 
                (fun channel -> Lwt_io.write channel file_data) in
              
              (* Get file size *)
              let size_bytes = 
                try Some ((Unix.stat temp_path).st_size) 
                with _ -> None 
              in
              
              (* Upload to S3 *)
              let%lwt s3_result = 
                Database.S3.upload_file ~album_id ~file_path:temp_path ~filename:s3_key
              in
              
              match s3_result with
              | Ok url -> 
                  (* Successfully uploaded to S3, now save to database *)
                  Dream.log "Successfully uploaded to S3: %s" url;
                  
                  (* Save record to database *)
                  let%lwt db_result = Dream.sql req (fun db ->
                    let%lwt result = Database.Db.add_photo 
                
                      ~album_id
                      ~filename:safe_filename
                      ~bucket_path:safe_filename
                      ~width:None
                      ~height:None
                      ~size_bytes
                      db
                    in
                    match result with
                    | Ok () -> Lwt.return (Ok ())
                    | Error e -> Lwt.return (Error (Caqti_error.show e))
                  ) in
                  
                  (* Clean up temp file *)
                  let%lwt () = Lwt_unix.unlink temp_path in
                  
                  (match db_result with
                  | Ok () -> 
                      uploaded := true;
                      Lwt.return_unit
                  | Error e ->
                      Dream.log "Database error: %s" e;
                      Lwt.return_unit)
                      
              | Error err -> 
                  Dream.log "S3 upload error: %s" (Database.S3.string_of_upload_error err);
                  
                  (* Clean up temp file *)
                  let%lwt _ = 
                    try%lwt Lwt_unix.unlink temp_path 
                    with _ -> Lwt.return_unit 
                  in
                  
                  Lwt.return_unit
            with exn ->
              Dream.log "Error processing file %s: %s" 
                original_filename (Printexc.to_string exn);
              
              (* Clean up temp file if it exists *)
              let%lwt _ = 
                if Sys.file_exists temp_path then
                  Lwt_unix.unlink temp_path 
                else
                  Lwt.return_unit
              in
              
              Lwt.return_unit
          ) photo_entries in
          
          (* Show success or error message based on uploads *)
          if !uploaded then
            (* Redirect back to album detail page *)
            Dream.redirect req ("/album/" ^ album_id)
          else
            Dream.html ~status:`Bad_Request "No files were uploaded successfully."
          
      | `Wrong_content_type ->
          Dream.html ~status:`Bad_Request "Invalid content type. Multipart form data expected."
      | _ ->
            Dream.html ~status:`Bad_Request "Invalid file upload"
      
    with Failure msg ->
      Dream.log "Failed to get album %s: %s" album_id msg;
      Dream.html ~status:`Internal_Server_Error ("Failed to retrieve album: " ^ msg)

