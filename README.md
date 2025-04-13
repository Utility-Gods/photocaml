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

### Multiple OPAM Switches

This project can be configured with multiple OPAM switches. If you encounter build issues related to dependencies, try the following:

1. Check your current switch:
   ```bash
   opam switch
   ```

2. Create a clean switch specifically for this project:
   ```bash
   opam switch create photocaml-clean ocaml-base-compiler.5.0.0 --no-install
   eval $(opam env)
   ```

3. Install core dependencies:
   ```bash
   opam install dune dream caqti caqti-lwt caqti-driver-sqlite3 lwt lwt_ppx uuidm ptime
   ```

### Common Build Issues

#### PPX Extension Issues

If you encounter errors with `ppx_rapper` or other PPX extensions, you may need to modify your approach:

1. Remove PPX dependencies from dune files:
   ```
   # Instead of using ppx_rapper
   (preprocess (pps ppx_rapper lwt_ppx))
   
   # Use only necessary extensions
   (preprocess (pps lwt_ppx))
   ```

2. Replace PPX-based queries with direct Caqti queries:
   ```ocaml
   (* Replace
   let create_album =
     [%rapper
       execute
         {sql| INSERT INTO ... |sql}
     ]
   *)
   
   (* With direct Caqti implementation *)
   let create_album ~id ~name ~description ~cover_image ~slug (module Db : Caqti_lwt.CONNECTION) =
     let query = 
       Caqti_request.exec 
         Caqti_type.(tup5 string string (option string) (option string) string)
         "INSERT INTO albums (id, name, description, cover_image, slug) VALUES (?, ?, ?, ?, ?)"
     in
     Db.exec query (id, name, description, cover_image, slug)
   ```

3. Clean the build directory before rebuilding:
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

- Use `Printf.printf "[DEBUG] message\n%!"` for console debugging during development
- When implementing new features, check existing files for coding patterns
- Database queries can be written directly with Caqti instead of using ppx_rapper
- Dream's form handling may need explicit content type handling

## 🔍 Troubleshooting

If you encounter issues with form submission, check the console logs and ensure proper content type handling in your form handler.
