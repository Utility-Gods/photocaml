# PhotoCaml Development Plan (TUI + Albums Revised)

**Goal:** Create a system with an interactive TUI (using Notty) for managing albums, uploading photos (with resizing) to S3 into albums, and generating shareable links for albums. A web app will display shared albums as galleries. Use SQLite for metadata storage.

**Methodology:** Implement the plan in discrete steps. **After each step, pause and wait for feedback before proceeding.**

---

## Phase 1: Core Setup & Dependencies

**Step 1.1: Add Core Dependencies**

*   **Task:** Add necessary package dependencies to the `photocaml.opam` file.
*   **Action:**
    *   Ensure `caqti-driver-sqlite3` (for SQLite) is present.
    *   Add `aws-s3` (or another suitable S3 OCaml library).
    *   Add `ocaml-images` (for image loading and resizing).
    *   Add `notty` and `notty-lwt` (for the TUI and async terminal events).
    *   Add `lwt` (for asynchronous operations).
    *   Add `uuidm` (for generating unique keys).
    *   Run `opam update && opam install caqti-driver-sqlite3 aws-s3 ocaml-images notty notty-lwt lwt uuidm`. *(Note: Package names might need adjustment based on availability in opam)*.
*   **Feedback:** Verify all packages are installed correctly. **Stop for feedback.**

**Step 1.2: Configure S3 Access**

*   **Task:** Plan how the TUI will get S3 credentials and configuration.
*   **Action:** Decide on a strategy (Environment variables recommended):
    *   Use Environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET_NAME`. This keeps secrets out of code and is simpler for a TUI.
    *   Document the required environment variables clearly for the user.
*   **Feedback:** Confirm the S3 configuration strategy (Environment Variables). **Stop for feedback.**

---

## Phase 2: Database Schema and Module (with Albums)**

**Step 2.1: Create/Update Database Module (`lib/database.ml`) & Schema**

*   **Task:** Define the database schema including albums and linking tables.
*   **Action:**
    *   Ensure `lib/database.ml` exists and has a corresponding `lib/dune` entry.
    *   Define/Update the `initialize_db` function:
        *   Connects to `photocaml.db`.
        *   Creates `albums` table if not exists: `id` INTEGER PRIMARY KEY, `name` TEXT NOT NULL, `created_at` TEXT NOT NULL.
        *   Creates `photos` table if not exists: `id` INTEGER PRIMARY KEY, `original_filename` TEXT, `s3_key_original` TEXT, `s3_key_medium` TEXT, `s3_key_thumbnail` TEXT, `uploaded_at` TEXT.
        *   Creates `album_photos` table if not exists: `album_id` INTEGER NOT NULL, `photo_id` INTEGER NOT NULL, FOREIGN KEY(`album_id`) REFERENCES `albums`(`id`), FOREIGN KEY(`photo_id`) REFERENCES `photos`(`id`), PRIMARY KEY (`album_id`, `photo_id`).
        *   Creates `share_links` table if not exists: `id` INTEGER PRIMARY KEY, `token` TEXT UNIQUE NOT NULL, `album_id` INTEGER NOT NULL, `created_at` TEXT NOT NULL, FOREIGN KEY(`album_id`) REFERENCES `albums`(`id`).
*   **Feedback:** Review the `database.ml` structure, `dune` file, and the revised schema definitions (`albums`, `album_photos`, modified `share_links`). **Stop for feedback.**

**Step 2.2: Implement Database Functions (Async, with Albums)**

*   **Task:** Implement async database functions for photos, albums, and sharing.
*   **Action:** Implement the following functions in `lib/database.ml` (returning `result Lwt.t`):
    *   `create_album(name)`: Inserts a new album, returns its ID.
    *   `get_all_albums()`: Retrieves `id` and `name` for all albums.
    *   `add_photo(original_filename, ...)`: Inserts a photo, returns its ID. (Same as before).
    *   `add_photo_to_album(photo_id, album_id)`: Links a photo to an album in `album_photos`.
    *   `get_photos_for_album(album_id)`: Retrieves all photo records (including S3 keys) belonging to a specific album by joining `photos` and `album_photos`.
    *   `create_album_share_link(album_id)`: Generates a token, inserts into `share_links` referencing the `album_id`, returns the token.
    *   `get_album_id_by_token(token)`: Retrieves `album_id` for a given token from `share_links`.
    *   *(Need to use `caqti-lwt`)*.
*   **Feedback:** Review the implementation and async nature (`Lwt`) of these database functions, ensuring they match the new schema. **Stop for feedback.**

---

## Phase 3: TUI Application Implementation (with Albums)**

**Step 3.1: Basic TUI Structure (`bin/tui_main.ml`)**

*   **Task:** Set up the main TUI entry point, event loop, and basic rendering.
*   **Action:**
    *   Create `bin/tui_main.ml`.
    *   Rename/Add an `executable` stanza named `tui_app` to `bin/dune`, linking the `database`, `notty`, `notty-lwt`, `lwt`, `aws-s3`, `images`, `uuidm` libraries.
    *   Implement the main function using `Lwt_main.run`.
    *   Initialize Notty terminal using `Notty_lwt.Term.create`.
    *   Set up a simple state record (e.g., current mode: `:MainMenu | :Upload | :ManageAlbums | :ShareAlbum`).
    *   Implement a main event loop using `Notty_lwt.Term.events` and `Lwt_stream.iter`.
    *   Handle basic events like quit (`Ctrl-C`).
    *   Implement a basic render function that takes the state and returns a `Notty.image` (initially just showing the mode).
    *   Render the initial image to the terminal.
*   **Feedback:** Review the basic TUI structure, `dune` file, Lwt/Notty setup, state definition, event loop, and initial rendering. Test running `dune exec ./bin/tui_app.exe` and quitting. **Stop for feedback.**

**Step 3.2: Implement Main Menu View and Navigation**

*   **Task:** Update the main menu for album functionality.
*   **Action:**
    *   Update render function for `:MainMenu` mode: Display options like "1. Manage Albums", "2. Upload Photos to Album", "3. Share Album", "Q. Quit".
    *   Update event loop: Handle key presses ('1', '2', '3', 'q') to switch application state to `:ManageAlbums`, `:Upload`, `:ShareAlbum` modes.
*   **Feedback:** Review the revised main menu options and navigation logic. **Stop for feedback.**

**Step 3.3: Implement TUI Album Management View/Logic**

*   **Task:** Build the UI to list and create albums.
*   **Action:**
    *   Define TUI state for `:ManageAlbums` mode: `album_list` (list of `id * name`), `selected_index` (int), `is_creating` (bool), `new_album_name` (string), `status_message` (string).
    *   Update render function for `:ManageAlbums`:
        *   Display the `album_list` (scrollable).
        *   Show a "[N]ew Album" option.
        *   If `is_creating`, show a text input for `new_album_name`.
        *   Display `status_message`.
    *   Update event loop for `:ManageAlbums`:
        *   On entering mode: Load albums using `Database.get_all_albums()` into `album_list`.
        *   Handle Up/Down arrows for selection.
        *   Handle 'N' key: Set `is_creating = true`, clear `new_album_name`.
        *   If `is_creating`: Handle character input for `new_album_name`. Handle 'Enter' key to call `Database.create_album(new_album_name)` (async), refresh `album_list`, set `is_creating = false`, update status. Handle 'Escape' to cancel creation.
        *   Handle 'B' key to return to `:MainMenu`.
*   **Feedback:** Review album listing, creation UI, state management, and async DB interaction for album management. **Stop for feedback.**

**Step 3.4: Implement TUI Upload View/Logic (Album-Aware)**

*   **Task:** Modify the upload process to target a specific album.
*   **Action:**
    *   Define TUI state for `:Upload` mode: `album_list` (list of `id * name`), `selected_album_index` (int option), `directory_path` (string, editable), `status_message` (string), `files_to_upload` (list), `upload_progress` (float).
    *   Update render function for `:Upload`:
        *   Display `album_list` (allow selection, potentially highlight `selected_album_index`). Show message "Select album to upload into".
        *   If an album is selected, show the directory path input field.
        *   Display status/progress area.
    *   Update event loop for `:Upload`:
        *   On entering mode: Load albums into `album_list`.
        *   Handle Up/Down arrows to select an album (`selected_album_index`).
        *   If an album is selected: Handle character input for `directory_path`. Handle 'Enter' on directory input to trigger upload.
        *   **Upload Process (Async):**
            *   Get the target `album_id` from `selected_album_index`.
            *   Read S3 config. Initialize S3 client.
            *   Scan directory, filter images.
            *   Loop through files (async):
                *   Resize image.
                *   Upload variants to S3.
                *   Call `Database.add_photo` (async) -> get `photo_id`.
                *   Call `Database.add_photo_to_album(photo_id, album_id)` (async).
                *   Update progress/status. Re-render.
            *   Update status: "Upload complete for album '<album_name>'. Press 'B' to go back." Re-render.
        *   Handle 'B' key to return to `:MainMenu`.
*   **Feedback:** Review the revised upload view requiring album selection, state changes, and updated async upload logic linking photos to the selected album. **Stop for feedback.**

**Step 3.5: Implement TUI Share Album View/Logic**

*   **Task:** Build the UI for selecting an album and generating its share link.
*   **Action:**
    *   Define TUI state for `:ShareAlbum` mode: `album_list` (list of `id * name`), `selected_index` (int), `origin_url` (string, editable), `generated_link` (string option), `status_message` (string).
    *   Update render function for `:ShareAlbum`:
        *   Display `album_list` (scrollable, highlight `selected_index`).
        *   Display Origin URL input field.
        *   Display `generated_link` or `status_message`.
    *   Update event loop for `:ShareAlbum`:
        *   On entering mode: Load albums into `album_list`.
        *   Handle Up/Down arrows for selection.
        *   Handle character input for Origin URL.
        *   Handle 'Enter' (when album selected and origin entered):
            *   Get selected `album_id`.
            *   Call `Database.create_album_share_link(album_id)` (async) -> get `token`.
            *   Construct full URL: `Printf.sprintf "%s/share/%s" origin_url token`.
            *   Update `generated_link` state. Re-render.
        *   Handle 'B' key to return to `:MainMenu`.
*   **Feedback:** Review the share view (now album-focused), state, event handling, and async DB interaction for sharing albums. **Stop for feedback.**

---

## Phase 4: Web App Album Viewer

**Step 4.1: Basic Web App Setup (`bin/main.ml`)**

*   **Task:** Set up the minimal Dream web server.
*   **Action:**
    *   Ensure `bin/main.ml` exists.
    *   Update `bin/dune` executable stanza for `main` to link `database` (using `caqti-lwt`) and `dream`.
    *   Initialize Dream. Call `Database.initialize_db` (async).
*   **Feedback:** Review the minimal web app setup and `dune` file. Ensure the web server runs. **Stop for feedback.**

**Step 4.2: Implement Web `/share/:token` Route (Album Gallery)**

*   **Task:** Create the endpoint to display a gallery of photos for a shared album.
*   **Action:**
    *   Add async GET route handler for `/share/:token`.
    *   Parse `token`.
    *   `let* album_id_opt = Database.get_album_id_by_token token in ...`
    *   If `album_id_opt` is `Some album_id`:
        *   `let* photo_records = Database.get_photos_for_album album_id in ...` (Returns a list of photo records).
        *   Generate HTML:
            *   Start HTML structure (`<html><head><title>Shared Album</title>...`). Add basic CSS for a grid layout.
            *   Iterate through `photo_records`:
                *   For each photo, construct its S3 URL (e.g., using `s3_key_thumbnail` or `s3_key_medium`).
                *   Append an `<img>` tag for the photo to the HTML body, potentially wrapped in a `div` for grid styling.
            *   Close HTML structure.
            *   Return `Dream.html generated_html`.
    *   Else (`album_id_opt` is `None` or DB error): `Dream.empty `Not_found`.
*   **Feedback:** Review the async `/share/:token` route logic, focusing on fetching multiple photos for an album and generating gallery HTML. Test accessing a valid album share link. **Stop for feedback.**

---

## Phase 5: Optional Enhancements

**(Adjusted for Albums)**

*   **Album Editing:** Allow renaming/deleting albums in TUI. Allow removing photos from albums.
*   **Photo Management:** View photos within an album in TUI? Delete individual photos?
*   **TUI Improvements:** Better navigation, visual cues, error handling.
*   **Web Gallery:** Improve web gallery styling, add photo filenames/captions, maybe pagination for huge albums, client-side filtering/sorting?
*   **Security:** Presigned URLs for gallery images.

**Next Steps (After Phase 4):**

*   Integrate actual segmentation.
*   Consider cloud storage.
*   Add user authentication if needed.
*   Refine error handling and UI/UX.
*   Plan deployment strategy. 