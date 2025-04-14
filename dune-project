(lang dune 3.14)

(name photocaml)

(generate_opam_files true)

(source
 (github utility-gods/photocaml))

(authors "Siddharth Jain <me@siddharthjain.in>")

(maintainers "Siddharth Jain <me@siddharthjain.in>")

(license LICENSE)

(documentation https://photocaml.utilitygods.com)

(package
 (name photocaml)
 (synopsis "A photosharing app in OCaml with Dream")
 (description "Upload photos to a bucket, segment them, and share them with a link.")
 (depends 
  ocaml
  dune
  dream
  caqti
  caqti-lwt
  caqti-driver-sqlite3
  lwt
  lwt_ppx
  ppx_rapper
  uuidm
  ptime
  dotenv
  cohttp
  cohttp-async
  cohttp-lwt-unix
  uri)
 (tags
  ("photosharing" "photos" "dream" "ocaml" "utility-gods")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
