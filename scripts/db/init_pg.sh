#!/bin/bash

# Load environment variables
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
else
  echo "Error: .env file not found"
  echo "Please copy .env.example to .env and update with your settings"
  exit 1
fi

# Check if POSTGRES_URL is set
if [ -z "$POSTGRES_URL" ]; then
  echo "Error: POSTGRES_URL not set in .env file"
  exit 1
fi

# Build and run initialization script
echo "Building initialization script..."
dune build scripts/db/init_pg.exe

echo "Initializing PostgreSQL database..."
dune exec scripts/db/init_pg.exe 