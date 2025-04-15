open Database

let () =
  let result = Lwt_main.run (
    let%lwt upload_result = S3.upload_file 
      ~album_id:"test" 
      ~file_path:"docs/1.jpg" 
      ~filename:"1.jpg"
    in
    Lwt.return upload_result
  ) in
  
  match result with
  | Ok url -> Printf.printf "Success! URL: %s\n" url
  | Error err -> Printf.printf "Failed: %s\n" (S3.string_of_upload_error err) 