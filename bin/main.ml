open Types

let sample_albums = [
  {id = "1"; name = "Summer Vacation"; description = "Photos from our trip to the beach"; photo_count = 24; cover_image = ""; created_at = "2025-03-15"};
  {id = "2"; name = "Family Gathering"; description = "Christmas celebration with the family"; photo_count = 12; cover_image = ""; created_at = "2025-04-01"};
]

let () =
  Dream.run ~interface:"0.0.0.0" ~port:4000 
  @@ Dream.logger
  @@ Dream.router [
    Dream.get "/" (fun _ ->
      let content = Template.Home.render () in
      Template.Layout.render
        ~title:"Home"
        ~content
        |> Dream.html
    );

    Dream.get "/album" (fun _ ->
      let content = Template.Album.render in
      Template.Layout.render
        ~title:"Albums"
        ~content
        |> Dream.html
    );

    Dream.get "/album/:id" (fun req ->
      let album_id = Dream.param req "id" in
      (* In a real app, you would fetch the album from the database *)
      let album = List.find_opt (fun a -> a.id = album_id) sample_albums in
      match album with
      | Some album ->
          let content = Template.Album_detail.render in
          Template.Layout.render
            ~title:album.name
            ~content
            |> Dream.html
      | None ->
          Dream.html ~status:`Not_Found "Album not found"
    );

    Dream.get "/static/**" (Dream.static "./static");
  ]
