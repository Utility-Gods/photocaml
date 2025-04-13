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


I am thinking that I can give user a bare minimum CLI to upload photos to a bucket, and then use the web app to segment them and share them with a link.

I can use sqlite to store the references to the photos and the links.

SO the CLI will only run locally and the web app will run on a server.
