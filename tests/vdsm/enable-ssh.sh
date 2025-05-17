#!/bin/bash

ENV_FILE=".env"

# Load .env if it exists
if [ -f "$ENV_FILE" ]; then
  echo "📦 Loading config from .env..."
  source "$ENV_FILE"
fi

# Prompt for missing fields
DSM_IP="${DSM_IP:-localhost}"
DSM_PORT="${DSM_PORT:-5000}"

if [ -z "$DSM_USER" ]; then
  read -p "👤 DSM Username: " DSM_USER
fi

if [ -z "$DSM_PASS" ]; then
  read -s -p "🔐 DSM Password for user '$DSM_USER': " DSM_PASS
  echo ""
fi

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
  echo "🔍 'jq' not found. Installing..."
  sudo apt update && sudo apt install -y jq
fi

# Login
echo "🔐 Logging in to DSM API at ${DSM_IP}:${DSM_PORT}..."
SID=$(curl -s -k "http://${DSM_IP}:${DSM_PORT}/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=${DSM_USER}&passwd=${DSM_PASS}&session=Core&format=sid" \
| jq -r '.data.sid')

if [[ "$SID" == "null" || -z "$SID" ]]; then
  echo "❌ Failed to login to DSM API (check username/password)"
  exit 1
fi

echo "✅ Logged in. Session ID: $SID"

# Enable SSH
echo "🛰 Enabling SSH remotely..."
RESPONSE=$(curl -s -k -X POST "http://${DSM_IP}:${DSM_PORT}/webapi/entry.cgi" \
  -d "api=SYNO.Core.Terminal" \
  -d "version=1" \
  -d "method=set" \
  -d "enable_ssh=true" \
  -d "_sid=${SID}")

if echo "$RESPONSE" | grep -q '"success":true'; then
  echo "✅ SSH successfully enabled on DSM"
else
  echo "❌ Failed to enable SSH"
  echo "$RESPONSE"
fi

# Logout
curl -s -k "http://${DSM_IP}:${DSM_PORT}/webapi/auth.cgi?api=SYNO.API.Auth&version=1&method=logout&session=Core&_sid=${SID}" > /dev/null
