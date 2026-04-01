#!/bin/bash
set -eo pipefail

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
NAMESPACE=${NAMESPACE:-"authority"}
TIER2_HOSTNAME=${TIER2_HOSTNAME:-"tls.authority.authority.ds.helsinki.tfds.io/"}
ORG_NAME=${ORG_NAME:-"FVH"}
ORG_UNIT=${ORG_UNIT:-"Data"}
COUNTRY=${COUNTRY:-"FI"}
PARTICIPANT_TYPE=${PARTICIPANT_TYPE:-"GOVERNANCE_AUTHORITY"}

echo "========================================================"
echo " Starting Simpl Identity Initialization"
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
CSR_FILE="csr.pem"
CERT_FILE="cert.pem"

# Execute Workflow
echo "-> Generating Keypair..."
curl -s -f -X POST "$AUTHORITY_AUTH_PROVIDER/v1/keypairs/generate" > /dev/null

echo "-> Generating CSR..."
curl -s -f -X POST "$AUTHORITY_AUTH_PROVIDER/v1/csr/generate" \
--header 'Content-Type: application/json' \
--data-raw "{
  \"commonName\": \"$TIER2_HOSTNAME\",
  \"country\": \"$COUNTRY\",
  \"organization\": \"$ORG_NAME\",
  \"organizationalUnit\": \"$ORG_UNIT\"
}" > "$CSR_FILE"

echo "-> Creating Participant in Identity Provider..."
PARTICIPANT_ID=$(curl -s -f -X POST "$AUTHORITY_IDENTITY_PROVIDER/v1/participants" \
--header 'Content-Type: application/json' \
--data-raw "{
  \"organization\": \"$ORG_NAME\",
  \"participantType\": \"$PARTICIPANT_TYPE\"
}" | sed -E 's/^"(.*)"$/\1/')
echo "   Participant ID: $PARTICIPANT_ID"

echo "-> Uploading CSR to Identity Provider..."
curl -s -f -X POST "$AUTHORITY_IDENTITY_PROVIDER/v1/participants/$PARTICIPANT_ID/csr" \
-F "csr=@$CSR_FILE" > /dev/null

echo "-> Downloading Signed Credential..."
curl -s -f "$AUTHORITY_IDENTITY_PROVIDER/v1/credentials/$PARTICIPANT_ID/download" \
-o "$CERT_FILE"

echo "-> Uploading Signed Credential to Authentication Provider..."
CREDENTIAL_ID=$(curl -s -f -X POST "$AUTHORITY_AUTH_PROVIDER/v1/credentials" \
-F "credential=@$CERT_FILE" | sed -E 's/^"(.*)"$/\1/')
echo "   Stored Credential ID: $CREDENTIAL_ID"

echo "========================================================"
echo " Initialization Complete!"
echo "========================================================"