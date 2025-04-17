type album = {
  id : string;
  name : string;
  description : string;
  photo_count : int;
  cover_image : string;
  created_at : string;
}

(* Shared photo_variant type for photo URL variants *)
type photo_variant = {
  thumbnail_url : string;
  medium_url : string;
  original_url : string;
  filename : string;
}
