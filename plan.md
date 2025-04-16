# PhotoCaml CLI Design

## Overview

A minimal CLI tool for uploading photos to albums, using the main library modules to interact with the database and S3.

## Core Functionality

### Commands

```bash
# Basic Commands
photocaml-cli upload <album-id> <paths...>    # Upload photos to an existing album
photocaml-cli albums                          # List available albums

# Paths can be:
# - Individual files:   photocaml-cli upload abc123 photo1.jpg photo2.jpg
# - Directories:       photocaml-cli upload abc123 ./vacation-pics/
# - Mixed:             photocaml-cli upload abc123 photo1.jpg ./more-pics/ photo2.jpg
# - Glob patterns:     photocaml-cli upload abc123 ./pics/*.jpg
```

## Implementation Strategy

### 1. Module Access
- CLI never accesses database or S3 directly
- All operations go through library modules:
  ```ocaml
  (* bin/photocaml_cli.ml *)
  
  (* Use the library's high-level functions *)
  let handle_upload album_id paths =
    (* Scanner module handles file discovery *)
    let* files = Scanner.scan_paths paths in
    
    (* Commands module handles all DB/S3 operations *)
    Commands.upload_photos ~album_id ~files
  ```

### 2. Library Structure
```ocaml
(* lib/commands.ml - High level operations *)
module Commands = struct
  let upload_photos ~album_id ~files =
    (* This module coordinates between DB and S3 *)
    (* CLI doesn't need to know how storage works *)
    ...

  let list_albums () =
    (* Handles database queries internally *)
    ...
end

(* lib/scanner.ml - File handling *)
module Scanner = struct
  let scan_paths paths =
    (* Handles file system operations *)
    ...
end
```

### 3. Data Flow
```
CLI (bin/photocaml_cli.ml)
     │
     │  Only uses high-level functions
     │
     ▼
Library Modules (lib/)
├── commands.ml  ────┐
│                   │ Internal coordination
├── scanner.ml      │ between modules
│                   ▼
└── database/      Database & S3
    ├── db.ml
    └── s3.ml
```

## Code Organization

```
lib/                       # Library modules
├── commands.ml           # High-level operations (uses database/)
├── scanner.ml            # File handling
├── database/            # Low-level modules (not used directly by CLI)
│   ├── db.ml           # Database operations
│   └── s3.ml           # Storage operations
└── dune                 # Library build config

bin/                      # Executable programs
├── main.ml              # Web application
├── dune                 # Build config
└── photocaml_cli.ml     # CLI (uses lib/commands.ml)
```

### Build Configuration

```scheme
;; lib/dune - Library modules
(library
 (name photocaml)
 (public_name photocaml)
 (libraries
  database
  cmdliner
  progress
  unix))

;; bin/dune - CLI executable
(executable
 (name photocaml_cli)
 (public_name photocaml-cli)
 (package photocaml)
 (libraries
  photocaml))            ; Only needs the main library
```

## Example Usage

```bash
# List available albums
$ photocaml-cli albums
ID                                    Name           Created
d7c0a208-e2c8-be97-e3e7-b427b77f087c Vacation 2024  2024-04-16

# Upload individual files
$ photocaml-cli upload d7c0a208-e2c8-be97-e3e7-b427b77f087c photo1.jpg photo2.jpg
Uploading to album "Vacation 2024"...
[====================] 2/2 files uploaded
```

## Development Steps

1. Add high-level modules to lib/:
   - Create commands.ml for coordinating operations
   - Create scanner.ml for file handling
   - These modules use database/ internally

2. Create minimal CLI executable:
   - Create bin/photocaml_cli.ml
   - Only use high-level functions from lib/

3. Implement functionality:
   - Scanner module handles all file operations
   - Commands module handles all DB/S3 operations
   - CLI just coordinates between user and library

4. Add progress reporting
5. Test with production database and storage

## Implementation Notes

- CLI never interacts with database or S3 directly
- All database and S3 operations happen through Commands module
- File operations happen through Scanner module
- Clean separation of concerns:
  - CLI: User interaction and argument parsing
  - Commands: High-level operations and coordination
  - Scanner: File system operations
  - Database: Low-level DB and S3 (used by Commands)

## Build and Run Process

1. Build and run during development:
   ```bash
   # Run CLI directly
   dune exec bin/photocaml_cli.exe -- [arguments]
   ```

2. Install and run:
   ```bash
   dune install
   photocaml-cli --help
   ```

## Module Dependency Flow

```
photocaml_cli.ml  # Only knows about Commands and Scanner
       │
       ▼
   commands.ml    # Coordinates operations using Database
       │
       ▼
   database/      # Handles low-level DB and S3 operations
``` 