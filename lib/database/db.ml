(* Main database module for PhotoCaml *)

(* Import Lwt syntax operators (let* for async/await style programming) *)
open Lwt.Syntax

(* Database connection pool 
   Type annotation ensures proper typing for the Caqti connection pool *)
let pool : (Caqti_lwt.connection, Caqti_error.t) Caqti_lwt.Pool.t option ref = ref None

(* Get database URL from environment 
   Example: postgres://user:pass@host:5432/dbname *)
let get_db_url () =
  match Sys.getenv_opt "POSTGRES_URL" with
  | Some url -> url
  | None -> 
      Printf.eprintf "Error: POSTGRES_URL environment variable not set\n";
      Printf.eprintf "Format: postgres://user:pass@host:5432/dbname\n";
      exit 1

(* Initialize the database connection pool 
   @param pool_size: Optional parameter to set max connections (default: 10)
   @return: Lwt result containing unit or error *)
let init ?(pool_size=10) () =
  let db_url = get_db_url () in
  let uri = Uri.of_string db_url in
  
  (* Create connection pool with specified size *)
  match Caqti_lwt.connect_pool ~max_size:pool_size uri with
  | Ok p -> 
      pool := Some p;
      let* () = Lwt_io.printl "Database initialized successfully" in
      Lwt.return_ok ()
  | Error err ->
      let* () = Lwt_io.eprintf "Error connecting to database: %s\n%!" 
        (Caqti_error.show err) in
      Lwt.return_error err

(* Get a connection from the pool 
   @return: Active connection pool or exits if not initialized *)
let get_connection () =
  match !pool with
  | Some p -> p
  | None ->
      Printf.eprintf "Error: Database not initialized\n%!";
      exit 1

(* Use a connection from the pool for a database operation
   @param f: Function that takes a connection and returns a result
   @return: Result of the database operation *)
let with_connection f =
  let pool = get_connection () in
  Caqti_lwt.Pool.use f pool

(* Clean up database connections 
   @return: Lwt unit promise after draining the connection pool *)
let cleanup () =
  match !pool with
  | Some p -> 
      let* () = Caqti_lwt.Pool.drain p in
      Lwt.return_unit
  | None -> 
      Lwt.return_unit 