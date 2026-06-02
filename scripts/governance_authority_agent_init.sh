#!/bin/bash
set -eo pipefail

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
NAMESPACE=${NAMESPACE:-"authority"}
TIER2_HOSTNAME=${TIER2_HOSTNAME:-"tls.authority.authority.ds.helsinki.tfds.io"}
ORG_NAME=${ORG_NAME:-"FVH"}
ORG_UNIT=${ORG_UNIT:-"Data"}
COUNTRY=${COUNTRY:-"FI"}
PARTICIPANT_TYPE=${PARTICIPANT_TYPE:-"GOVERNANCE_AUTHORITY"}

echo "========================================================"
echo " Starting Simpl Identity Initialization (v3.1.0 API)"
echo " Target Namespace:  $NAMESPACE"
echo " Hostname (CN):     $TIER2_HOSTNAME"
echo " Organization:      $ORG_NAME ($COUNTRY)"
echo " Participant Type:  $PARTICIPANT_TYPE"
echo "========================================================"

# Establish Port Forwarding
echo "-> Establishing port forwarding..."
kubectl -n "$NAMESPACE" port-forward svc/authentication-provider 8080:8080 > /dev/null 2>&1 &
AUTH_PF_PID=$!

kubectl -n "$NAMESPACE" port-forward svc/identity-provider 8090:8080 > /dev/null 2>&1 &
ID_PF_PID=$!

trap "echo '-> Cleaning up port-forwarding jobs...'; kill $AUTH_PF_PID $ID_PF_PID 2>/dev/null || true" EXIT

echo "-> Waiting for connections to establish..."
sleep 10

export AUTHORITY_AUTH_PROVIDER="http://localhost:8080"
export AUTHORITY_IDENTITY_PROVIDER="http://localhost:8090"
CSR_FILE="csr.json"
CREDENTIAL_FILE="credential.json"

# Execute Workflow
echo "-> 1. Creating Keypair..."
KEYPAIR_RES=$(curl -s -f -X POST "$AUTHORITY_AUTH_PROVIDER/tier1/v2/keypairs" \
  -H 'Content-Type: application/json' \
  -d '{"name": "initialization-authority"}')
KEYPAIR_ID=$(echo "$KEYPAIR_RES" | jq -r '.id')
echo "   Keypair ID: $KEYPAIR_ID"

echo "-> 2. Generating CSR..."
curl -s -f -X POST "$AUTHORITY_AUTH_PROVIDER/tier1/v2/keypairs/$KEYPAIR_ID/csr" \
  -H 'Content-Type: application/json' \
  -d "{
    \"commonName\": \"$TIER2_HOSTNAME\",
    \"country\": \"$COUNTRY\",
    \"organization\": \"$ORG_NAME\",
    \"organizationalUnit\": \"$ORG_UNIT\"
  }" > "$CSR_FILE"

echo "-> 3. Creating Participant in Identity Provider..."
PARTICIPANT_RES=$(curl -s -f -X POST "$AUTHORITY_IDENTITY_PROVIDER/tier1/v2/participants" \
  -H 'Content-Type: application/json' \
  -d "{
    \"organization\": \"$ORG_NAME\",
    \"participantType\": \"$PARTICIPANT_TYPE\",
    \"isAuthority\": true
  }")
PARTICIPANT_ID=$(echo "$PARTICIPANT_RES" | jq -r '.id')
echo "   Participant ID: $PARTICIPANT_ID"

echo "-> 4. Uploading CSR to Identity Provider..."
curl -s -f -X PUT "$AUTHORITY_IDENTITY_PROVIDER/tier1/v2/participants/$PARTICIPANT_ID/csr" \
  -H 'Content-Type: application/json' \
  -d @"$CSR_FILE" > /dev/null

echo "-> 5. Creating Credentials..."
curl -s -f -X POST "$AUTHORITY_IDENTITY_PROVIDER/tier1/v2/participants/$PARTICIPANT_ID/credentials" \
  -H 'Content-Type: application/json' \
  -d '{"reason": "INITIALIZATION_REASON"}' > "$CREDENTIAL_FILE"

# Extract credential content block from response
CRED_B64=$(jq -r '.content' "$CREDENTIAL_FILE")

echo "-> 6. Uploading Credentials to Authentication Provider..."
# Use jq to safely construct the JSON payload to avoid multiline string breakage
jq -n --arg content "$CRED_B64" '{"reason": "initialization-authority", "content": $content}' > final_payload.json

curl -s -f -X POST "$AUTHORITY_AUTH_PROVIDER/tier1/v2/credentials" \
  -H 'Content-Type: application/json' \
  -d @final_payload.json > /dev/null

rm final_payload.json

echo "========================================================"
echo " Initialization Complete!"
echo "========================================================"
