#!/usr/bin/env bash
# test-extension-client.sh
# Manual test client for the M5 localhost extension auth API.
#
# Usage: ./scripts/test-extension-client.sh <PAIRING_CODE> <password>

set -euo pipefail

BASE_URL="http://127.0.0.1:17487"
PAIRING_CODE="${1:?Usage: $0 <PAIRING_CODE> <password>}"
PASSWORD="${2:?Usage: $0 <PAIRING_CODE> <password>}"
REQUEST_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"

echo "==> GET /v1/status"
curl -sS "$BASE_URL/v1/status" | python3 -m json.tool
echo

echo "==> POST /v1/pair"
PAIR_RESPONSE="$(curl -sS -X POST "$BASE_URL/v1/pair" \
  -H "Content-Type: application/json" \
  -d "{\"protocolVersion\":1,\"pairingCode\":\"$PAIRING_CODE\",\"clientName\":\"Test Client\"}")"
echo "$PAIR_RESPONSE" | python3 -m json.tool

ACCESS_TOKEN="$(echo "$PAIR_RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')"
echo

echo "==> POST /v1/verify"
VERIFY_RESPONSE="$(curl -sS -X POST "$BASE_URL/v1/verify" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d "{\"protocolVersion\":1,\"requestId\":\"$REQUEST_ID\",\"origin\":\"https://example.com\",\"password\":\"$PASSWORD\",\"keystrokes\":[{\"character\":\"t\",\"dwellTime\":0.08,\"flightTime\":0},{\"character\":\"e\",\"dwellTime\":0.09,\"flightTime\":0.04}]}")"
echo "$VERIFY_RESPONSE" | python3 -m json.tool
echo

GRANTED="$(echo "$VERIFY_RESPONSE" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["granted"]).lower())')"

if [[ "$GRANTED" == "true" ]]; then
  echo "==> POST /v1/fill-approve"
  curl -sS -X POST "$BASE_URL/v1/fill-approve" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "{\"protocolVersion\":1,\"requestId\":\"$(uuidgen | tr '[:upper:]' '[:lower:]')\",\"origin\":\"https://example.com\",\"verificationRequestId\":\"$REQUEST_ID\"}" \
    | python3 -m json.tool
else
  echo "Verify was not granted (expected if password/rhythm do not match enrolled profile)."
  echo "fill-approve skipped."
fi

echo
echo "Done."
