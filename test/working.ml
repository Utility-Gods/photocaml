open Lwt
open Cohttp
open Cohttp_lwt_unix

let postData = ref "<file contents here>";;

let reqBody = 
  let uri = Uri.of_string "https://s3.us-east-005.backblazeb2.com/photocaml/test.jpg" in
  let headers = Header.init ()
    |> fun h -> Header.add h "x-amz-content-sha256" "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    |> fun h -> Header.add h "Content-Type" "image/png"
    |> fun h -> Header.add h "X-Amz-Date" "••••••"
    |> fun h -> Header.add h "Authorization" "••••••"
  in
  let body = Cohttp_lwt.Body.of_string !postData in

  Client.call ~headers ~body `PUT uri >>= fun (_resp, body) ->
  body |> Cohttp_lwt.Body.to_string >|= fun body -> body

let () =
  let respBody = Lwt_main.run reqBody in
  print_endline (respBody)