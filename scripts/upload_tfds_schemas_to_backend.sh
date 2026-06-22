#!/bin/bash

# ======================================================================================
# Schema Manager API Uploader
# ======================================================================================
# This script automates the uploading of strictly validated PascalCase SHACL shapes
# directly to the Schema Manager backend API, bypassing the UI.
# ======================================================================================

ENDPOINT="https://schema-manager-be.authority.ds.helsinki.tfds.io/v1/schemas"
SHAPES_DIR="../tfds-schemas/TFDS-shapes"

if [ -z "$1" ]; then
  echo "Usage: $0 <JWT_ACCESS_TOKEN>"
  echo "Please provide a valid Keycloak access token (WITHOUT the 'Bearer ' prefix)."
  exit 1
fi

TOKEN="$1"

# Function to upload a single schema
upload_schema() {
  local FILE_NAME=$1
  local SCHEMA_NAME=$2
  local TITLE=$3
  local DESC=$4

  echo "--------------------------------------------------------"
  echo "Uploading: $SCHEMA_NAME ($FILE_NAME)"

  local FILE_PATH="${SHAPES_DIR}/${FILE_NAME}"

  if [ ! -f "$FILE_PATH" ]; then
    echo "❌ ERROR: File $FILE_PATH does not exist. Skipping."
    return 1
  fi

  # Execute the CURL command and capture the HTTP response code
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$ENDPOINT" \
    -H "Authorization: ${TOKEN}" \
    -F "name=${SCHEMA_NAME}" \
    -F "title=${TITLE}" \
    -F "description=${DESC}" \
    -F "resourceType=Data" \
    -F "schemaFile=@${FILE_PATH}")

  if [ "$HTTP_CODE" -eq 201 ]; then
    echo "✅ Success: $SCHEMA_NAME created (HTTP 201)."
  elif [ "$HTTP_CODE" -eq 409 ] || [ "$HTTP_CODE" -eq 400 ]; then
     # Note: The schema manager often throws a 400 with a "duplicate/already exists" detail
     # if you try to re-upload. This script assumes 4xx means it might already exist.
    echo "⚠️ Warning: Server returned HTTP $HTTP_CODE. It may already exist, or token may be invalid."
  else
    echo "❌ Failed: Server returned HTTP $HTTP_CODE."
  fi
}

echo "Starting Schema Manager Upload Process..."

# 1. Base Data Offering (Must come first)
upload_schema "DataOfferingShape.ttl" "DataOfferingShape" "Data Offering Base Schema" "Base Data Offering Schema"

# 2. TFDS Extensions
upload_schema "TrafficFlowDataOfferingShape.ttl" "TrafficFlowDataOfferingShape" "Traffic Flow Data Offering" "TFDS Traffic Flow Data Offering"
upload_schema "TrafficDisturbanceDataOfferingShape.ttl" "TrafficDisturbanceDataOfferingShape" "Traffic Disturbance Data Offering" "TFDS Traffic Disturbance Data Offering"
upload_schema "IdeaValidationDataOfferingShape.ttl" "IdeaValidationDataOfferingShape" "IDEA Validation Data Offering" "TFDS IDEA Validation Data Offering"
upload_schema "AirQualityDataOfferingShape.ttl" "AirQualityDataOfferingShape" "Air Quality Data Offering" "TFDS Air Quality Data Offering"

echo "--------------------------------------------------------"
echo "Upload process complete."