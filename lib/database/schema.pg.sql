-- Schema for PhotoCaml PostgreSQL database

-- Enable UUID extension for generating IDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE albums (
    -- Use UUID for IDs
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    cover_image TEXT,
    slug TEXT UNIQUE NOT NULL,
    -- Use timestamptz for proper timezone handling
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE photos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    album_id UUID NOT NULL,
    filename TEXT NOT NULL,
    bucket_path TEXT NOT NULL,
    width INTEGER,
    height INTEGER,
    size_bytes BIGINT,  -- Using BIGINT for larger file sizes
    uploaded_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
);

CREATE TABLE shares (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    album_id UUID NOT NULL,
    share_token TEXT NOT NULL UNIQUE,
    is_public BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
);

-- Create indexes for better query performance
CREATE INDEX idx_photos_album ON photos(album_id);
CREATE INDEX idx_shares_album ON shares(album_id);
CREATE INDEX idx_shares_token ON shares(share_token);
CREATE INDEX idx_albums_slug ON albums(slug);

-- Add comments for documentation
COMMENT ON TABLE albums IS 'Photo albums containing groups of related images';
COMMENT ON TABLE photos IS 'Individual photos belonging to albums';
COMMENT ON TABLE shares IS 'Share tokens for providing access to albums'; 