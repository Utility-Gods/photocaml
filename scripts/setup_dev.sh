#!/bin/bash

# Exit on error
set -e

# Environment setup first, since we need POSTGRES_URL
if [ ! -f .env ]; then
    echo "No .env file found. Creating default configuration..."
    cat > .env << EOL
# Database Configuration
POSTGRES_URL=postgres://postgres:postgres@localhost:5432/photocaml
PGUSER=postgres
PGPASSWORD=postgres
PGHOST=localhost
PGPORT=5432
PGDATABASE=photocaml

# Storage Configuration
B2_ACCESS_KEY=your_access_key
B2_SECRET_KEY=your_secret_key
B2_ENDPOINT=your_endpoint
B2_BUCKET_NAME=your_bucket
B2_REGION=your_region
EOL
    echo "Created default .env file. Please update with your actual configuration."
fi

# Load environment variables
set -a
source .env
set +a

# Check required variables
if [ -z "$POSTGRES_URL" ]; then
    echo "Error: POSTGRES_URL not set in .env file"
    echo "Please ensure your .env file contains the database configuration"
    exit 1
fi

# Check if PostgreSQL is accepting connections
if ! psql -c '\q' 2>/dev/null; then
    echo "Error: Cannot connect to PostgreSQL"
    echo "Please check your database configuration and ensure PostgreSQL is running"
    exit 1
fi

# Check if database exists and create if needed
if psql -lqt | cut -d \| -f 1 | grep -qw "$PGDATABASE"; then
    echo "Database '$PGDATABASE' already exists, skipping creation"
else
    echo "Creating database '$PGDATABASE'..."
    createdb
fi

# Build project
echo "Building project..."
dune build

# Run database migrations
echo "Running database migrations..."
dune exec scripts/db/init_pg.exe

echo "Development environment setup complete!"
echo "You can now start using photocaml with:"
echo "  dune exec bin/main.exe -- --help" 