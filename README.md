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
opam install dune dream caqti caqti-lwt caqti-driver-postgresql lwt lwt_ppx uuidm ptime
```

### Database Setup

The application uses PostgreSQL as its database. The schema is managed through SQL files in the `lib/database` directory.

#### Local Development Setup

For local development, you can initialize the database using:

```bash
# Set your database URL in .env file:
POSTGRES_URL=postgres://user:pass@localhost:5432/dbname

# Initialize the database schema
dune exec scripts/db/init_pg.exe
```

#### Production Setup

In production, database initialization and migrations are handled through Docker container initialization. The schema will be automatically applied when the database container starts up.

The schema file is located at:
```
lib/database/schema.pg.sql
```

Note: The schema requires the `uuid-ossp` PostgreSQL extension, which will be automatically enabled during initialization.

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
   opam install --yes dune dream caqti caqti-lwt caqti-driver-postgresql lwt lwt_ppx ppx_rapper ppx_rapper_lwt uuidm ptime
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
   - `caqti`, `caqti-lwt`, and `caqti-driver-postgresql`: PostgreSQL database connectivity
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
   (libraries caqti caqti-lwt caqti-driver-postgresql ppx_rapper_lwt ...)
   
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
│   │   ├── db.ml      # connection pooling
│   │   ├── schema.pg.sql  # PostgreSQL schema
│   │   └── dune       # database lib config
├── scripts/
│   └── db/
│       ├── init_pg.ml  # database initialization script
│       └── dune        # script config
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
   - Ensure PostgreSQL is running and accessible
   - Check schema matches what queries expect
   - Verify database connection string in .env file
   - Run database initialization script if needed

## 📷 Using the CLI

### Build the CLI

```bash
dune build bin/cli/photocaml_cli.exe
```

The CLI executable will be available at `_build/default/bin/cli/photocaml_cli.exe`

### Running the CLI

You can use the CLI in three different ways:

1. **Interactive Menu Mode** (Recommended for beginners):
   ```bash
   _build/default/bin/cli/photocaml_cli.exe menu
   ```
   This will present you with an easy-to-use menu with the following options:
   - List all albums
   - Upload photos to album
   - Exit

2. **Direct Commands**:

   a. List all albums:
   ```bash
   _build/default/bin/cli/photocaml_cli.exe list
   ```

   b. Upload photos to an album:
   ```bash
   _build/default/bin/cli/photocaml_cli.exe upload <album_id> <directory_with_photos>
   ```
   Example:
   ```bash
   _build/default/bin/cli/photocaml_cli.exe upload a95a7319-049e-d8e8-a2e6-bc9fd4888d81 /path/to/photos
   ```

### CLI Help

To see all available commands and options:
```bash
_build/default/bin/cli/photocaml_cli.exe --help
```

For help with a specific command:
```bash
_build/default/bin/cli/photocaml_cli.exe <command> --help
```
Example:
```bash
_build/default/bin/cli/photocaml_cli.exe upload --help
```
