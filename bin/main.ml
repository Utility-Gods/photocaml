let () =
  Dream.run ~interface:"0.0.0.0" ~port:4000 
  @@ Dream.logger
  @@ Dream.router [
    Dream.get "/" (fun _ ->
      Layout.render
        ~title:"Home"
        ~content:"<h1 class='text-2xl text-red-600'>Welcome to PhotoCaml</h1>
                  <p class='text-xl text-gray-500'>Upload photos to a bucket, segment them, and share them with a link.</p>
        "
    );

    Dream.get "/static/**" (Dream.static "./static");
  ]

