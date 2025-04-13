let render ~title ~content =
  Dream.html (Printf.sprintf {|
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>%s</title>
      <script src="https://cdn.tailwindcss.com"></script>
      <script src="https://unpkg.com/htmx.org@1.9.2"></script>
    </head>
    <body class="p-4">
      %s
    </body>
    </html>
  |} title content)

