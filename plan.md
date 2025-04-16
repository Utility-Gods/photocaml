# PhotoCaml CLI Design

## Overview

A minimal CLI tool for uploading photos to albums, connecting directly to the production database and S3 storage.

## Core Functionality

### Commands

```bash
# Basic Commands
photocaml upload <album-id> <paths...>    # Upload photos to an existing album
photocaml albums                          # List available albums

# Paths can be:
# - Individual files:   photocaml upload abc123 photo1.jpg photo2.jpg
# - Directories:       photocaml upload abc123 ./vacation-pics/
# - Mixed:             photocaml upload abc123 photo1.jpg ./more-pics/ photo2.jpg
# - Glob patterns:     photocaml upload abc123 ./pics/*.jpg
```

## Implementation Strategy

### 1. Database Connection
- Direct connection to production Postgres using `caqti`
- Reuse existing database schema and queries
- Environment variables for database configuration:
  ```bash
  POSTGRES_URL=postgres://user:pass@host:5432/dbname
  ```

### 2. Storage Connection
- Reuse existing S3/B2 configuration and upload logic
- Share environment variables with main app:
  ```bash
  B2_ACCESS_KEY=xxx
  B2_SECRET_KEY=xxx
  B2_ENDPOINT=xxx
  B2_BUCKET_NAME=xxx
  B2_REGION=xxx
  ```

### 3. File Handling
- Recursive directory scanning
- Support for common image formats:
  ```
  .jpg, .jpeg, .png, .gif, .webp, .heic
  ```
- Skip non-image files automatically
- Handle file name collisions with timestamps
- Progress bar showing:
  - Files found/scanned
  - Current upload progress
  - Overall progress

### 4. CLI Structure
- Simple binary using `cmdliner`
- Load configuration from same `.env` file as main app
- Minimal error handling and user feedback

## Code Organization

```
cli/
├── bin/
│   └── main.ml          # Entry point
├── lib/
│   ├── commands.ml      # Command implementations
│   ├── db.ml           # Database operations (reused)
│   ├── s3.ml           # Storage operations (reused)
│   └── scanner.ml      # File/directory scanner
└── dune                # Build configuration
```

## Example Usage

```bash
# List available albums
$ photocaml albums
ID                                    Name           Created
d7c0a208-e2c8-be97-e3e7-b427b77f087c Vacation 2024  2024-04-16

# Upload individual files
$ photocaml upload d7c0a208-e2c8-be97-e3e7-b427b77f087c photo1.jpg photo2.jpg
Uploading to album "Vacation 2024"...
[====================] 2/2 files uploaded

# Upload a directory
$ photocaml upload d7c0a208-e2c8-be97-e3e7-b427b77f087c ./vacation-pics/
Scanning directory...
Found 42 images
Uploading to album "Vacation 2024"...
[===============>    ] 31/42 files uploaded

# Upload mixed paths
$ photocaml upload d7c0a208-e2c8-be97-e3e7-b427b77f087c profile.jpg ./vacation-pics/*.jpg
Scanning paths...
Found 15 images
Uploading to album "Vacation 2024"...
[====================] 15/15 files uploaded
```

## Development Steps

1. Set up CLI project structure
2. Copy and adapt database/storage modules
3. Implement file/directory scanner
4. Implement basic commands
5. Add progress reporting
6. Test with production database 