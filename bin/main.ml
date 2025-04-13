module Handlers = struct
  let generate_slug name =
    let open Str in
    name 
    |> String.lowercase_ascii
    |> global_replace (regexp " +") "-"
    |> global_replace (regexp "[^a-z0-9-]") ""

  let create_album_handler req =
    match%lwt Dream.form req with
    | `Ok params ->
        let name = List.assoc "name" params in
        let description = List.assoc_opt "description" params in
        let id = Database.Db.generate_id () in
        let slug = generate_slug name in
        
        (try%lwt
          (* Dream.sql expects callback returning 'a Lwt.t, raising exception on error *) 
          let%lwt () = Dream.sql req (fun db ->
            let%lwt result = Database.Db.create_album ~id ~name ~description ~cover_image:None ~slug db in
            match result with
            | Ok () -> Lwt.return_unit
            | Error e -> Lwt.fail (Failure (Caqti_error.show e))
          ) in
          Dream.redirect req "/album"
        with Failure msg ->
          Dream.log "Failed to create album: %s" msg;
          Dream.html ~status:`Internal_Server_Error ("Failed to create album: " ^ msg)
        )
        
    | `Wrong_content_type ->
        Dream.html ~status:`Bad_Request "Wrong content type"
    | _ -> (* Catch other form errors *) 
        Dream.html ~status:`Bad_Request "Invalid form submission"
        
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
            
            (* Create unique filename for S3 *)
            let safe_filename = 
              Filename.basename original_filename
              |> String.map (fun c -> if c = ' ' then '_' else c)
            in
            let timestamp = Int.to_string (int_of_float (Unix.time ())) in
            let unique_filename = timestamp ^ "_" ^ safe_filename in
            
            (* Save to temp file first *)
            let temp_path = Filename.concat temp_dir unique_filename in
            
            (* Generate unique ID for the database *)
            let id = Database.Db.generate_id () in
            
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
                Database.S3.upload_file ~album_id ~file_path:temp_path ~filename:unique_filename
              in
              
              match s3_result with
              | Ok url -> 
                  (* Successfully uploaded to S3, now save to database *)
                  Dream.log "Successfully uploaded to S3: %s" url;
                  
                  (* Save record to database *)
                  let%lwt db_result = Dream.sql req (fun db ->
                    let%lwt result = Database.Db.add_photo 
                      ~id
                      ~album_id
                      ~filename:safe_filename
                      ~bucket_path:url
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
                  Dream.log "S3 upload error: %s" err;
                  
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
end

let () =
  Dream.run ~interface:"0.0.0.0" ~port:4000 
  @@ Dream.logger
  @@ Dream.sql_pool "sqlite3:db.sqlite"
  @@ Dream.router [
    Dream.get "/" (fun _ ->
      let content = Template.Home.render () in
      Template.Layout.render
        ~title:"Home"
        ~content
        |> Dream.html
    );

    Dream.get "/album" (fun _ ->
      let content = Template.Album.render in
      Template.Layout.render
        ~title:"Albums"
        ~content
        |> Dream.html
    );

    Dream.get "/album/new" (fun _ ->
      let content = Template.New_album.render () in
      Template.Layout.render
        ~title:"Create New Album"
        ~content
        |> Dream.html
    );

    Dream.post "/album/new" Handlers.create_album_handler;

    Dream.get "/album/:id" (fun req ->
      let album_id = Dream.param req "id" in
      (try%lwt
        (* Get album details *) 
        let%lwt album = Dream.sql req (fun db ->
            let%lwt result = Database.Db.get_album ~id:album_id db in
            match result with
            | Ok album_record -> Lwt.return album_record
            | Error e -> Lwt.fail (Failure (Caqti_error.show e)) (* Includes "not found" *) 
          )
        in
        let content = Template.Album_detail.render in
        Template.Layout.render
          ~title:"Album Details"
          ~content
          |> Dream.html
      with Failure msg ->
        Dream.log "Failed to get album %s: %s" album_id msg;
        (* We could check `msg` here to distinguish "not found" if needed *) 
        Dream.html ~status:`Internal_Server_Error ("Failed to retrieve album: " ^ msg)
      )
    );
    
    (* Upload page routes *)
    Dream.get "/album/:id/upload" (fun req ->
      let album_id = Dream.param req "id" in
      (try%lwt
        (* Get album for the upload page *)
        let%lwt album = Dream.sql req (fun db ->
            let%lwt result = Database.Db.get_album ~id:album_id db in
            match result with
            | Ok album_record -> Lwt.return album_record
            | Error e -> Lwt.fail (Failure (Caqti_error.show e))
          )
        in
        let content = Template.Upload.render in
        Template.Layout.render
          ~title:"Upload Photos"
          ~content
          |> Dream.html
      with Failure msg ->
        Dream.log "Failed to get album %s for upload: %s" album_id msg;
        Dream.html ~status:`Internal_Server_Error ("Failed to access album: " ^ msg)
      )
    );
    
    (* Handle photo uploads *)
    Dream.post "/album/:id/upload" Handlers.upload_photo_handler;

    (* Serve static files including uploads *)
    Dream.get "/static/**" (Dream.static "./static");
  ]
