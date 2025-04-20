open Types
open Handler
open Database

let () =
  (* Use simple Printf for logging *)
  Random.self_init(); (* Initialize random seed for ID generation *)
  
  (* Load environment variables *)
  let () = Dotenv.export ~debug:true () in
  let db_url = get_db_url () in
  
  Dream.run ~interface:"0.0.0.0" ~port:4000 
  @@ Dream.logger
  @@ Dream.memory_sessions
  @@ Dream.origin_referrer_check  (* Added CSRF protection *)
  @@ (fun handler req -> 
      let meth = Dream.method_to_string (Dream.method_ req) in
      let target = Dream.target req in
      Printf.printf "[REQUEST] %s %s\n%!" meth target;
      handler req)
  @@ Dream.sql_pool db_url
  @@ Dream.router [

  
    (* Public share route for albums *)
    Dream.get "/share/:token" share_album_handler;

    (* Paginated API for share photos *)
    Dream.get "/api/share_photos" share_photos_api_handler;

    (* Serve static files including uploads *)
    Dream.get "/static/**" (Dream.static "./static");
  ]
