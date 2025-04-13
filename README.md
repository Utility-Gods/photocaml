# PhotoCaml App in OCaml with Dream

Simple web app using OCaml + Dream.

## 🔧 Setup

```bash
opam switch create . 5.1.1
eval $(opam env)
opam install dune dream
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
│   └── main.ml         # app entry point
├── lib/                # place your reusable modules here
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
