#!/bin/bash

# Load environment variables
source .env

# Remove trailing slash from endpoint if present
B2_ENDPOINT=${B2_ENDPOINT%/}

# Check if environment variables are set
if [ -z "$B2_ACCESS_KEY" ] || [ -z "$B2_SECRET_KEY" ] || [ -z "$B2_ENDPOINT" ] || [ -z "$B2_BUCKET_NAME" ] || [ -z "$B2_REGION" ]; then
    echo "Error: Required environment variables are not set"
    echo "Please ensure B2_ACCESS_KEY, B2_SECRET_KEY, B2_ENDPOINT, B2_BUCKET_NAME, and B2_REGION are set"
    exit 1
fi

# Test file path
TEST_FILE="docs/1.jpg"
if [ ! -f "$TEST_FILE" ]; then
    echo "Error: Test file $TEST_FILE not found"
    exit 1
fi

# Generate timestamps
DATE_STAMP=$(TZ=UTC date +%Y%m%d)
AMZ_DATE=$(TZ=UTC date +%Y%m%dT%H%M%SZ)

# Calculate content type
CONTENT_TYPE=$(file -b --mime-type "$TEST_FILE")

# Calculate payload hash using awk
PAYLOAD_HASH=$(openssl dgst -sha256 -hex "$TEST_FILE" | awk '{print $NF}')

# Define request components
HTTP_METHOD="PUT"
CANONICAL_URI="/$B2_BUCKET_NAME/test/1.jpg"
CANONICAL_QUERYSTRING=""
SIGNED_HEADERS="content-type;host;x-amz-content-sha256;x-amz-date"
# Use printf to ensure proper newline interpretation
CANONICAL_HEADERS=$(printf "content-type:%s\nhost:%s\nx-amz-content-sha256:%s\nx-amz-date:%s\n" "$CONTENT_TYPE" "$B2_ENDPOINT" "$PAYLOAD_HASH" "$AMZ_DATE")

# Create canonical request using printf
CANONICAL_REQUEST=$(printf "%s\n%s\n%s\n%s\n%s\n%s" "$HTTP_METHOD" "$CANONICAL_URI" "$CANONICAL_QUERYSTRING" "$CANONICAL_HEADERS" "$SIGNED_HEADERS" "$PAYLOAD_HASH")

# Calculate canonical request hash using awk
# Note: We still use printf '%s' here for the input to openssl
CANONICAL_REQUEST_HASH=$(printf '%s' "$CANONICAL_REQUEST" | openssl dgst -sha256 -hex | awk '{print $NF}')

# Create string to sign using printf
STRING_TO_SIGN=$(printf "AWS4-HMAC-SHA256\n%s\n%s/%s/s3/aws4_request\n%s" "$AMZ_DATE" "$DATE_STAMP" "$B2_REGION" "$CANONICAL_REQUEST_HASH")

# Calculate signing key
kSecret="AWS4$B2_SECRET_KEY"
# Calculate kDate (binary) then convert to hex
kDate=$(printf '%s' "$DATE_STAMP" | openssl dgst -sha256 -mac HMAC -macopt "key:$kSecret" -binary)
kDateHex=$(echo -n "$kDate" | xxd -p -c 256)
# Calculate kRegion (binary) using kDateHex, then convert to hex
kRegion=$(printf '%s' "$B2_REGION" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"$kDateHex" -binary)
kRegionHex=$(echo -n "$kRegion" | xxd -p -c 256)
# Calculate kService (binary) using kRegionHex, then convert to hex
kService=$(printf '%s' "s3" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"$kRegionHex" -binary)
kServiceHex=$(echo -n "$kService" | xxd -p -c 256)
# Calculate kSigning (binary) using kServiceHex, then convert to hex
kSigning=$(printf '%s' "aws4_request" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"$kServiceHex" -binary)
kSigningHex=$(echo -n "$kSigning" | xxd -p -c 256)

# Calculate signature using awk and kSigningHex
SIGNATURE=$(printf '%s' "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"$kSigningHex" -hex | awk '{print $NF}')

# Create authorization header
AUTH_HEADER="AWS4-HMAC-SHA256 Credential=$B2_ACCESS_KEY/$DATE_STAMP/$B2_REGION/s3/aws4_request,SignedHeaders=$SIGNED_HEADERS,Signature=$SIGNATURE"

echo "Uploading $TEST_FILE to s3://$B2_BUCKET_NAME/test/1.jpg"
echo "Using endpoint: $B2_ENDPOINT"
echo "Content-Type: $CONTENT_TYPE"
echo "Authorization: $AUTH_HEADER"

# Make the request
curl -v -X PUT "https://$B2_ENDPOINT/$B2_BUCKET_NAME/test/1.jpg" \
    -H "Host: $B2_ENDPOINT" \
    -H "Content-Type: $CONTENT_TYPE" \
    -H "Authorization: $AUTH_HEADER" \
    -H "x-amz-date: $AMZ_DATE" \
    -H "x-amz-content-sha256: $PAYLOAD_HASH" \
    --data-binary "@$TEST_FILE"

echo -e "\nUpload complete. Check the response above for success or error messages." 