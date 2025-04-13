let () = 
  Dream.run ~port:4000
  @@ Dream.logger
  @@ Dream.router[
    Dream.get "/a" (fun _ -> Dream.html "<h1>Hello, world!</h1>");
  ]
