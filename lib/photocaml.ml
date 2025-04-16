(* Main library module *)

module Database = Database

module Cli = struct
  module Commands = struct
    let list_albums () = Lwt.return (Ok ())
    let upload _ _ = Lwt.return (Ok ())
  end

  module Scanner = struct
    let scan_paths _ = Lwt.return []
  end
end 