(lang dune 3.14)

(name photocaml)


(source
 (github utility-gods/photocaml))

(authors "Siddharth")

(maintainers "Siddharth")

(license MIT)

(documentation https://url/to/documentation)

(generate_opam_files false)

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
  dream
  ppx_rapper
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
