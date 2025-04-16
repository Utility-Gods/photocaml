(** Main library module *)

module Database = Database

module Cli : sig
  module Commands : sig
    val list_albums : unit -> (unit, string) result Lwt.t
    (** List all available albums *)

    val upload : string -> string list -> (unit, string) result Lwt.t
    (** Upload photos to an album
        @param album_id The ID of the target album
        @param paths List of file/directory paths to process *)
  end

  module Scanner : sig
    val scan_paths : string list -> string list Lwt.t
    (** Scan multiple paths for images
        @param paths List of file/directory paths to scan
        @return List of image file paths *)
  end
end 