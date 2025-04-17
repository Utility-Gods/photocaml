(* Initialize PostgreSQL database for PhotoCaml
   This script:
   1. Loads environment from .env file
   2. Connects to PostgreSQL using caqti
   3. Reads and executes schema.pg.sql
   4. Reports success/failure
*)

open Lwt.Infix
open Lwt.Syntax
open Caqti_request.Infix

(* Read schema file *)
let read_schema () =
  let ic = open_in "lib/database/schema.pg.sql" in
  let content = really_input_string ic (in_channel_length ic) in
  close_in ic;
  content

(* Split SQL into separate statements *)
let split_sql sql =
  let statements = String.split_on_char ';' sql in
  List.filter (fun s -> 
    let s = String.trim s in
    String.length s > 0 && not (String.starts_with ~prefix:"--" s)
  ) statements

(* Get database URL from environment *)
let get_db_url () =
  (* Load .env file *)
  let () = Dotenv.export ~debug:true () in
  
  (* Get POSTGRES_URL from .env *)
  match Sys.getenv_opt "POSTGRES_URL" with
  | Some url -> url
  | None -> 
      Printf.eprintf "Error: POSTGRES_URL environment variable not set in .env file\n";
      Printf.eprintf "Format: postgres://user:pass@host:5432/dbname\n";
      exit 1

(* Execute a single SQL statement *)
let exec_statement (module Db : Caqti_lwt.CONNECTION) sql =
  let request = 
    (Caqti_type.unit ->. Caqti_type.unit)
    @@ sql
  in
  Db.exec request ()

(* Initialize database *)
let init_db () =
  let schema_sql = read_schema () in
  let statements = 
    (* Add uuid-ossp extension before other statements *)
    "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"" :: split_sql schema_sql 
  in
  let db_url = get_db_url () in
  
  (* Connect and execute schema *)
  let%lwt connection = 
    Caqti_lwt.connect (Uri.of_string db_url) >>= function
    | Ok conn -> Lwt.return conn
    | Error err ->
        Printf.eprintf "Error connecting to database: %s\n" (Caqti_error.show err);
        exit 1
  in

  (* Execute schema as a single transaction *)
  let (module Db : Caqti_lwt.CONNECTION) = connection in
  
  let%lwt result =
    let* start_result = Db.start () in
    match start_result with
    | Error err -> Lwt.return_error err
    | Ok () ->
        (* Execute each statement *)
        let rec exec_all = function
          | [] -> Lwt.return_ok ()
          | stmt :: rest ->
              let* exec_result = exec_statement (module Db) stmt in
              match exec_result with
              | Error err -> 
                  let* _ = Db.rollback () in
                  Lwt.return_error err
              | Ok () -> exec_all rest
        in
        let* exec_result = exec_all statements in
        match exec_result with
        | Error err -> Lwt.return_error err
        | Ok () ->
            (* Commit transaction *)
            let* commit_result = Db.commit () in
            match commit_result with
            | Error err -> Lwt.return_error err
            | Ok () -> Lwt.return_ok ()
  in

  match result with
  | Ok () ->
      Printf.printf "Database schema created successfully!\n";
      Lwt.return_unit
  | Error err ->
      Printf.eprintf "Error creating schema: %s\n" (Caqti_error.show err);
      exit 1

(* Main entry point *)
let () =
  Lwt_main.run (init_db ()) 