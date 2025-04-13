# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands
- Build project: `dune build`
- Run server: `dune exec ./bin/main.exe`
- Run tests: `dune test`
- Run single test: `dune exec ./test/test_photocaml.exe -- -test-name <test_name>`
- Clean build artifacts: `dune clean`

## Code Style Guidelines
- **Formatting**: Follow OCaml style with 2-space indentation
- **Naming**: Use snake_case for functions and variables, module names in CamelCase
- **Error Handling**: Use Result monad with explicit error messages; use try%lwt for exception handling
- **Templates**: EML templates define either values (let render = <html>) or functions (let render () = <html>)
- **Types**: Define module types at the top of modules, use records with field names
- **Database**: Use ppx_rapper for SQL queries with typed parameters
- **Web**: Use Dream framework with HTML templating via dream_eml
- **Imports**: Place open statements at the top of files, only use what's needed
- **Unused Values**: Use underscore (_) for unused function parameters
- **Comments**: Use (** *) for documentation comments and (* *) for inline comments

## Common Issues
- If build fails with warning errors, check the dune file for warning flags
- Template render functions without parameters should be called without parentheses