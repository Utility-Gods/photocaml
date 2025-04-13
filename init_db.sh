#!/bin/bash
set -e

echo "Creating and initializing SQLite database..."

# Remove existing database if it exists
if [ -f db.sqlite ]; then
  echo "Removing existing database..."
  rm db.sqlite
fi

# Create a new empty database
echo "Creating new database..."
touch db.sqlite

# Initialize the database with schema
echo "Initializing database with schema..."
sqlite3 db.sqlite < lib/database/schema.sql

# Verify tables were created
echo "Verifying database tables..."
sqlite3 db.sqlite ".tables"

echo "Database initialization complete."