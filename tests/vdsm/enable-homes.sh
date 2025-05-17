#!/bin/bash
#
# NOTE:
# If this script fails with error code 3103, you can enable user home directories manually via the DSM Web GUI:
#
# 1. Log in to DSM at http://localhost:5000
# 2. Go to Control Panel → User → Advanced tab
# 3. Check the box: "Enable user home service"
# 4. Apply the changes and retry SSH access
#

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
SID=$(curl -s -k "http://${DSM_IP}:${DSM_PORT}/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=${DSM_USER}&passwd=${DSM_PASS}&session=Core&format=sid" | jq -r '.data.sid')

if [[ "$SID" == "null" || -z "$SID" ]]; then
  echo "❌ Failed to login to DSM API"
  exit 1
fi

echo "✅ Logged in. Session ID: $SID"

# Enable home directories
echo "📁 Enabling user home directories..."
RESPONSE=$(curl -s -k -X POST "http://${DSM_IP}:${DSM_PORT}/webapi/entry.cgi" \
  -d "api=SYNO.Core.User.Home" \
  -d "version=1" \
  -d "method=set" \
  -d "enable=true" \
  -d "_sid=${SID}")

if echo "$RESPONSE" | grep -q '"success":true'; then
  echo "✅ Home directories enabled successfully"
else
  echo "❌ Failed to enable home directories:"
  echo "$RESPONSE"
  echo ""
  echo "📎 To enable user home directories manually via DSM:"
  echo "  1. Log in to DSM at http://${DSM_IP}:${DSM_PORT}"
  echo "  2. Go to Control Panel → User & Group → Advanced tab"
  echo "  3. Check the box: \"Enable user home service\""
  echo "  4. Apply the changes and try sending your public key for SSH access (./vdsm-control.sh => 10)."
  exit 1
fi

# Logout
curl -s -k "http://${DSM_IP}:${DSM_PORT}/webapi/auth.cgi?api=SYNO.API.Auth&version=1&method=logout&session=Core&_sid=${SID}" > /dev/null