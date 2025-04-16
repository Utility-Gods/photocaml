(lang dune 3.14)

(name photocaml)

(generate_opam_files true)

(source
 (github username/photocaml))

(authors "Your Name")

(maintainers "Your Name")

(license LICENSE)

(documentation https://url/to/documentation)

(package
 (name photocaml)
 (synopsis "Photo album management tool")
 (description "A CLI tool for managing photo albums with PostgreSQL and S3 storage")
 (depends
  (ocaml (>= 4.14.0))
  dune
  lwt
  lwt_ppx
  caqti
  caqti-lwt
  caqti-driver-postgresql
  dotenv
  uri
  uuidm
  ppx_deriving
  ppx_deriving_yojson
  yojson
  digestif
  (alcotest :with-test)
  (alcotest-lwt :with-test))
 (tags
  (photos cli postgresql s3)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
