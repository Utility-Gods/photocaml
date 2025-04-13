# PhotoCaml App in OCaml with Dream

Simple web app using OCaml + Dream for photo sharing.

## 🔧 Setup

### Standard Setup

```bash
opam switch create . 5.1.1
eval $(opam env)
opam install dune dream
```

### Dependency Management

This project requires specific dependencies to run properly. The core dependencies include:

```bash
opam install dune dream caqti caqti-lwt caqti-driver-sqlite3 lwt lwt_ppx uuidm ptime
```

## 🧪 Environment Setup and Troubleshooting

### OPAM Switch Management

This project requires specific OCaml dependencies managed through OPAM switches. The default switch with OCaml 5.3.0 is recommended.

1. Check your current switch:
   ```bash
   opam switch
   ```

2. Use the default switch (recommended):
   ```bash
   opam switch default
   eval $(opam env)
   ```

3. Install all required dependencies:
   ```bash
   opam install --yes dune dream caqti caqti-lwt caqti-driver-sqlite3 lwt lwt_ppx ppx_rapper ppx_rapper_lwt uuidm ptime
   ```

### Handling Build Locks

If dune build fails with a lock error, you can clear the locks:

```bash
rm -f _build/.lock
dune clean
dune build
```

### Dependencies and Context

The project requires the following dependencies to be installed:

1. **Core Libraries**:
   - `dune`: Build system
   - `dream`: Web framework
   - `lwt` and `lwt_ppx`: Asynchronous programming

2. **Database Libraries**:
   - `caqti`, `caqti-lwt`, and `caqti-driver-sqlite3`: Database connectivity
   - `ppx_rapper` and `ppx_rapper_lwt`: SQL query type safety with PPX

3. **Utilities**:
   - `uuidm`: UUID generation
   - `ptime`: Time handling

All of these must be installed in your active OPAM switch for the project to build and run correctly.

### Advanced: Managing PPX Extensions

If you encounter issues with PPX extensions specifically, you can try alternate approaches:

1. **Ensure ppx_rapper is correctly installed**:
   ```bash
   opam install ppx_rapper ppx_rapper_lwt
   ```

2. **Configure dune files properly**:
   ```
   # Make sure libraries includes ppx_rapper_lwt
   (libraries caqti caqti-lwt caqti-driver-sqlite3 ppx_rapper_lwt ...)
   
   # And preprocess includes both ppx_rapper and lwt_ppx
   (preprocess (pps ppx_rapper lwt_ppx))
   ```

3. **Clean build artifacts thoroughly**:
   ```bash
   rm -rf _build/
   dune clean
   dune build
   ```

#### Form Submission Issues

If you encounter form submission issues with Dream:

1. Ensure the form has the correct enctype:
   ```html
   <form action="/album/new" method="POST" enctype="application/x-www-form-urlencoded">
   ```

2. Consider manual form data parsing for debugging:
   ```ocaml
   let%lwt body = Dream.body req in
   Printf.printf "[DEBUG] Form body: %s\n%!" body;
   ```

## 🚀 Run the App

```bash
dune exec ./bin/main.exe
```

Visit: [http://localhost:4000](http://localhost:4000)

## 🛠 Build

```bash
dune build
```

Binary will be in `_build/default/bin/main.exe`

To copy it out:

```bash
cp _build/default/bin/main.exe ./photo_app
```

## 🧱 Project Structure

```
.
├── .opam/              # local opam switch (env + packages)
├── _build/             # dune build artifacts
├── bin/
│   ├── dune            # dune config for executable
│   ├── main.ml         # app entry point
│   └── *.eml.html      # dream templates
├── lib/
│   ├── database/       # database interaction
│   │   ├── database.ml # database queries
│   │   ├── s3.ml       # S3 integration
│   │   └── schema.sql  # database schema
│   └── dune            # library configuration
├── dune-project        # project metadata
├── photocaml.opam      # package dependencies
└── README.md           # this file
```

## 🛑 Stop the App

Press `Ctrl+C` in the terminal.

## 🌐 Change Port

Edit `main.ml`:

```ocaml
Dream.run ~interface:"0.0.0.0" ~port:4000
```

## 📝 Development Notes

### Debugging

For effective debugging:

```ocaml
(* Define debug helpers at the top of your file *)
let debug fmt = Printf.ksprintf (fun s -> Printf.printf "[DEBUG] %s\n%!" s) fmt
let error fmt = Printf.ksprintf (fun s -> Printf.printf "[ERROR] %s\n%!" s) fmt

(* Use them in your code *)
debug "Creating album: %s" name;
error "Database error: %s" err_msg;
```

- Always use `%!` at the end of your format strings to force flushing
- Set explicit content types in HTML forms
- Check existing files for coding patterns when implementing new features
- For database queries, ppx_rapper provides type safety but requires proper installation

### Forms and Templating

For forms to work correctly:

```html
<form action="/path" method="POST" enctype="application/x-www-form-urlencoded">
  <!-- Form elements -->
</form>
```

The Dream handler should use standard form parsing:

```ocaml
match%lwt Dream.form req with
| `Ok params ->
    let name = List.assoc "name" params in
    (* Continue processing *)
| `Wrong_content_type ->
    Dream.html ~status:`Bad_Request "Wrong content type"
| _ -> 
    Dream.html ~status:`Bad_Request "Invalid form submission"
```

## 🔍 Troubleshooting

### Common Issues

1. **Form submission fails**: 
   - Add `enctype="application/x-www-form-urlencoded"` to your forms
   - Use `match%lwt Dream.form req with` pattern for handling form data
   - Check logs for content-type issues
   - Ensure the database is initialized (see [Database Setup](#-database-setup))
   - Form submission errors like "Invalid form submission" often indicate missing database tables

2. **Build errors**:
   - Clear locks: `rm -f _build/.lock && dune clean`
   - Make sure dependencies are installed in your active switch
   - Update opam: `opam update && opam upgrade`

3. **Database errors**:
   - Ensure SQLite database exists and is accessible
   - Check schema matches what queries expect
   - Initialize database before first run

## 🗃️ Database Setup

The application uses SQLite for data storage. You must initialize the database before running the application for the first time:

### Database Initialization

```bash
# Execute the database initialization script
dune build init_db.exe && dune exec ./init_db.exe
```

This script:
1. Creates a new SQLite database file (`db.sqlite`)
2. Applies the schema from `lib/database/schema.sql`
3. Creates the required tables (albums, photos, shares)

### Manual Database Initialization

If you prefer to initialize the database manually:

```bash
# Remove existing database if it exists
rm -f db.sqlite

# Create a new database with the schema
sqlite3 db.sqlite < lib/database/schema.sql

# Verify tables were created
sqlite3 db.sqlite ".tables"
```

The database should contain the following tables:
- `albums`: Stores album information (id, name, description, etc.)
- `photos`: Stores photo information linked to albums
- `shares`: Stores album sharing details

### Database Initialization Script

To use the database initialization script, create the following files:

**init_db.ml**:
```ocaml
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
```

**dune** (root directory):
```
(executable
 (name init_db)
 (libraries sqlite3))
```

Then run `dune build init_db.exe && dune exec ./init_db.exe` to initialize the database.
