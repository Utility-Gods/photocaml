let read_schema () =
  let ic = open_in "lib/database/schema.sql" in
  let content = really_input_string ic (in_channel_length ic) in
  close_in ic;
  content

let () =
  (* Remove existing database if it exists *)
  if Sys.file_exists "db.sqlite" then (
    Printf.printf "Removing existing database...\n%!";
    Sys.remove "db.sqlite"
  );

  (* Get schema SQL *)
  let schema_sql = read_schema () in
  
  (* Create database connection *)
  let db = Sqlite3.db_open "db.sqlite" in
  
  (* Execute schema SQL *)
  Printf.printf "Creating database schema...\n%!";
  match Sqlite3.exec db schema_sql with
  | Sqlite3.Rc.OK -> 
      Printf.printf "Database schema created successfully!\n%!";
      (* List tables *)
      let table_stmt = Sqlite3.prepare db "SELECT name FROM sqlite_master WHERE type='table'" in
      let rec list_tables tables =
        match Sqlite3.step table_stmt with
        | Sqlite3.Rc.ROW ->
            let table_name = Sqlite3.column_text table_stmt 0 in
            list_tables (table_name :: tables)
        | Sqlite3.Rc.DONE -> tables
        | _ -> tables
      in
      let tables = list_tables [] in
      Printf.printf "Created tables: %s\n%!" (String.concat ", " tables);
      ignore (Sqlite3.finalize table_stmt);
      ignore (Sqlite3.db_close db)
  | err -> 
      Printf.printf "Error creating schema: %s\n%!" (Sqlite3.Rc.to_string err);
      ignore (Sqlite3.db_close db);
      exit 1