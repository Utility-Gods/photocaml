module S3 = S3

module Db = struct
  module T = struct
    type album = {
      id: string;
      name: string;
      description: string option;
      cover_image: string option;
      slug: string;
      created_at: Ptime.t;
    }

    type photo = {
      id: string;
      album_id: string;
      filename: string;
      bucket_path: string;
      width: int option;
      height: int option;
      size_bytes: int option;
      uploaded_at: Ptime.t;
    }

    type share = {
      id: string;
      album_id: string;
      share_token: string;
      is_public: bool;
      expires_at: Ptime.t option;
      created_at: Ptime.t;
    }

    type photo_paths = {
      original: string;
      thumbnail: string;
      medium: string;
    }
  end

    

  let create_album =
    [%rapper
      execute
        {sql|
          INSERT INTO albums (id, name, description, cover_image, slug)
          VALUES (%string{id}, %string{name}, %string?{description}, %string?{cover_image}, %string{slug})
        |sql}
    ]

  
  let get_album =
    [%rapper
      get_one
        {sql|
          SELECT * FROM albums WHERE id = %string{id}
        |sql}
    ]


  let add_photo =
    [%rapper
      execute
        {sql|
          INSERT INTO photos (id, album_id, filename, bucket_path, width, height, size_bytes)
          VALUES (%string{id}, %string{album_id}, %string{filename}, %string{bucket_path}, %int?{width}, %int?{height}, %int?{size_bytes})
        |sql}
    ]


  let get_photos_by_album =
    [%rapper
      get_many
        {sql|
          SELECT * FROM photos WHERE album_id = %string{album_id} ORDER BY uploaded_at DESC
        |sql}
    ]


  let create_share =
    [%rapper
      execute
        {sql|
          INSERT INTO shares (id, album_id, share_token, is_public, expires_at)
          VALUES (%string{id}, %string{album_id}, %string{share_token}, %bool{is_public}, %ptime?{expires_at})
        |sql}
    ]

  

  let make_photo_paths photo : T.photo_paths = 
    let open T in
    let base_path = photo.bucket_path in
    let ext = Filename.extension photo.filename in
    {
      original = base_path;
      thumbnail = base_path ^ "_thumbnail" ^ ext;
      medium = base_path ^ "_medium" ^ ext;
    }
    
  (* Generate a unique ID for a new record *)
  let generate_id () =
    let random_bytes = Bytes.create 16 in
    for i = 0 to 15 do
      Bytes.set random_bytes i (Char.chr (Random.int 256))
    done;
    let hex_of_char c =
      let code = Char.code c in
      let hi = code lsr 4 in
      let lo = code land 0xf in
      let to_hex n = if n < 10 then Char.chr (n + 48) else Char.chr (n + 87) in
      (to_hex hi, to_hex lo)
    in
    let buffer = Buffer.create 32 in
    for i = 0 to 15 do
      let (hi, lo) = hex_of_char (Bytes.get random_bytes i) in
      Buffer.add_char buffer hi;
      Buffer.add_char buffer lo;
      if i = 3 || i = 5 || i = 7 || i = 9 then Buffer.add_char buffer '-';
    done;
    Buffer.contents buffer
end
