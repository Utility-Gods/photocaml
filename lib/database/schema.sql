CREATE TABLE albums (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  cover_image TEXT,
  slug TEXT UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE photos (
  id TEXT PRIMARY KEY,
  album_id TEXT NOT NULL,
  filename TEXT NOT NULL,
  bucket_path TEXT NOT NULL,
  width INTEGER,
  height INTEGER,
  size_bytes INTEGER,
  uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (album_id) REFERENCES albums(id)
);

CREATE TABLE shares (
  id TEXT PRIMARY KEY,
  album_id TEXT NOT NULL,
  share_token TEXT NOT NULL UNIQUE,
  is_public BOOLEAN DEFAULT FALSE,
  expires_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (album_id) REFERENCES albums(id)
);

CREATE INDEX idx_photos_album ON photos(album_id);
CREATE INDEX idx_shares_album ON shares(album_id);
CREATE INDEX idx_shares_token ON shares(share_token);
CREATE INDEX idx_albums_slug ON albums(slug);
