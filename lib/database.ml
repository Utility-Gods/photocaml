open Lwt.Syntax (* Ope Lwt.Let_syntax *)
open Lwt.Infix (* Ope Lwt.Syntax *)
open Caqti_request.Infix
open Caqti_type.Std

let src = Logs.Src.create "photocaml.database"

module Log = (val Logs.src_log src : Logs.LOG)

let db_file = "photocaml.db"
let db_uri = Printf.sprintf "sqlite3:%s" db_file

let pool = ref None

let get_pool () =
  match !pool with
  | Some p -> p
  | None ->
      let p = Caqti_lwt.connect_pool ~max_size:10 (Uri.of_string db_uri) in
      pool := Some p;
      p

(* Helper function to execute a query using the pool *)
let use_pool query params =
  let pool = get_pool () in
  Caqti_lwt.Pool.use (fun (module Conn : Caqti_lwt.CONNECTION) ->
      Log.debug (fun m -> m "Executing query: %a" Caqti_request.pp query);
      Conn.find query params
    ) pool
  |> Lwt_result.map_err Caqti_error.show

(* Helper function to execute an update/insert using the pool *)
let exec_pool query params =
  let pool = get_pool () in
  Caqti_lwt.Pool.use (fun (module Conn : Caqti_lwt.CONNECTION) ->
      Log.debug (fun m -> m "Executing exec query: %a" Caqti_request.pp query);
      Conn.exec query params
    ) pool
  |> Lwt_result.map_err Caqti_error.show

(* Helper function to get the last insert ID (specific to SQLite) *)
let get_last_insert_id (module Conn : Caqti_lwt.CONNECTION) () =
  let query = [%rapper get_one {"sql|SELECT last_insert_rowid()|sql"} ()] in
  Conn.find query ()

let initialize_db () =
  Log.info (fun m -> m "Initializing database at %s" db_uri);
  let pool = get_pool () in
  Caqti_lwt.Pool.use
    (fun (module Conn : Caqti_lwt.CONNECTION) ->
      let create_albums_table =
        [%rapper execute
          {"sql|CREATE TABLE IF NOT EXISTS albums (
                   id INTEGER PRIMARY KEY AUTOINCREMENT,
                   name TEXT NOT NULL UNIQUE,
                   created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                 )|sql"}
          ()
        ]
      in
      let create_photos_table =
        [%rapper execute
          {"sql|CREATE TABLE IF NOT EXISTS photos (
                   id INTEGER PRIMARY KEY AUTOINCREMENT,
                   original_filename TEXT,
                   s3_key_original TEXT UNIQUE,
                   s3_key_medium TEXT UNIQUE,
                   s3_key_thumbnail TEXT UNIQUE,
                   uploaded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                 )|sql"}
          ()
        ]
      in
      let create_album_photos_table =
        [%rapper execute
          {"sql|CREATE TABLE IF NOT EXISTS album_photos (
                   album_id INTEGER NOT NULL,
                   photo_id INTEGER NOT NULL,
                   FOREIGN KEY(album_id) REFERENCES albums(id) ON DELETE CASCADE,
                   FOREIGN KEY(photo_id) REFERENCES photos(id) ON DELETE CASCADE,
                   PRIMARY KEY (album_id, photo_id)
                 )|sql"}
          ()
        ]
      in
      let create_share_links_table =
        [%rapper execute
          {"sql|CREATE TABLE IF NOT EXISTS share_links (
                   id INTEGER PRIMARY KEY AUTOINCREMENT,
                   token TEXT UNIQUE NOT NULL,
                   album_id INTEGER NOT NULL,
                   created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                   FOREIGN KEY(album_id) REFERENCES albums(id) ON DELETE CASCADE
                 )|sql"}
          ()
        ]
      in
      (* Helper for executing initialization queries *)
      let exec_init query = 
        Log.debug (fun m -> m "Executing init query: %a" Caqti_request.pp query);
        let*! result = Conn.exec query () in
        Caqti_lwt.or_fail result
      in

      let* _ = exec_init create_albums_table in
      Log.debug (fun m -> m "Albums table created or already exists.");
      let* _ = exec_init create_photos_table in
      Log.debug (fun m -> m "Photos table created or already exists.");
      let* _ = exec_init create_album_photos_table in
      Log.debug (fun m -> m "Album_photos table created or already exists.");
      let* _ = exec_init create_share_links_table in
      Log.debug (fun m -> m "Share_links table created or already exists.");
      Lwt.return_ok ())
    pool
  |> Lwt_result.map_err Caqti_error.show

(* Album Functions *)

let create_album ~name:album_name =
  let query =
    [%rapper
      execute
        {"sql|INSERT INTO albums(name) VALUES (%string:album_name)|sql"}
        function_out
    ]
  in
  let pool = get_pool () in
  Caqti_lwt.Pool.use (fun (module Conn : Caqti_lwt.CONNECTION) ->
      let*! exec_result = Conn.exec query album_name in
      match Caqti_lwt.or_fail exec_result with
      | Error e -> Lwt.return_error e
      | Ok () ->
          let*! id_result = get_last_insert_id (module Conn) () in
          Caqti_lwt.or_fail id_result
  ) pool
  |> Lwt_result.map_err Caqti_error.show

let get_all_albums () =
  let query =
    [%rapper
      get_many
        {"sql|SELECT id, name FROM albums ORDER BY name ASC|sql"}
        ()
        function_out
        (id := int, name := string)
    ]
  in
  use_pool query ()

(* Photo Functions *)

let add_photo ~original_filename ~s3_key_original ~s3_key_medium ~s3_key_thumbnail =
  let query =
    [%rapper
      execute
        {"sql|
           INSERT INTO photos (original_filename, s3_key_original, s3_key_medium, s3_key_thumbnail)
           VALUES (%string:original_filename, %string:s3_key_original, %string:s3_key_medium, %string:s3_key_thumbnail)
        |sql"}
        function_out
    ]
  in
  let pool = get_pool () in
  Caqti_lwt.Pool.use (fun (module Conn : Caqti_lwt.CONNECTION) ->
      let params =
        ( original_filename,
          s3_key_original,
          s3_key_medium,
          s3_key_thumbnail )
      in
      let*! exec_result = Conn.exec query params in
      match Caqti_lwt.or_fail exec_result with
      | Error e -> Lwt.return_error e
      | Ok () ->
          let*! id_result = get_last_insert_id (module Conn) () in
          Caqti_lwt.or_fail id_result
    ) pool
  |> Lwt_result.map_err Caqti_error.show

let add_photo_to_album ~photo_id ~album_id =
  let query =
    [%rapper
      execute
        {"sql|INSERT INTO album_photos (album_id, photo_id) VALUES (%int:album_id, %int:photo_id)|sql"}
        function_out
    ]
  in
  exec_pool query (album_id, photo_id)

(* Define a record type for photo data *) 
type photo_record = {
  id : int;
  original_filename : string option;
  s3_key_original : string option;
  s3_key_medium : string option;
  s3_key_thumbnail : string option;
  uploaded_at : string;
}

let get_photos_for_album ~album_id =
  let query =
    [%rapper
      get_many
        {"sql|
          SELECT p.id, p.original_filename, p.s3_key_original, p.s3_key_medium, p.s3_key_thumbnail, p.uploaded_at
          FROM photos p
          JOIN album_photos ap ON p.id = ap.photo_id
          WHERE ap.album_id = %int:album_id
          ORDER BY p.uploaded_at ASC
        |sql"}
        function_out
        (id := int,
         original_filename :=? string,
         s3_key_original :=? string,
         s3_key_medium :=? string,
         s3_key_thumbnail :=? string,
         uploaded_at := string)
        -> photo_record (* Map to the record type *)
    ]
  in
  use_pool query album_id

(* Share Link Functions *)

let create_album_share_link ~album_id =
  let token = Uuidm.v4_gen (Random.State.make_self_init ()) () |> Uuidm.to_string in
  let query =
    [%rapper
      execute
        {"sql|INSERT INTO share_links (token, album_id) VALUES (%string:token, %int:album_id)|sql"}
        function_out
    ]
  in
  let*! result = exec_pool query (token, album_id) in
  match result with
  | Ok () -> Lwt.return_ok token
  | Error e -> Lwt.return_error e

let get_album_id_by_token ~token =
  let query =
    [%rapper
      get_opt
        {"sql|SELECT album_id FROM share_links WHERE token = %string:token|sql"}
        function_out
        (album_id := int)
    ]
  in
  use_pool query token

let () =
  Logs.set_reporter (Logs.format_reporter ());
  Logs.set_level (Some Logs.Info) (* Adjust log level as needed *) 