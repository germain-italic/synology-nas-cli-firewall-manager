#!/bin/bash

# This script updates the "name" field of a rule containing a specific IP
# Usage: ./update_firewall_rule_name.sh <IP> <new_name>

# Load configuration and language files
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Load the .env file
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
else
    echo "Error: .env file not found. Please create one based on .env.dist."
    exit 1
fi

# Load the appropriate language file
if [ "$LANG" = "en" ]; then
    if [ -f "$SCRIPT_DIR/lang/en.sh" ]; then
        source "$SCRIPT_DIR/lang/en.sh"
    fi
else
    if [ -f "$SCRIPT_DIR/lang/fr.sh" ]; then
        source "$SCRIPT_DIR/lang/fr.sh"
    fi
fi

if [ "$#" -ne 2 ]; then
    echo "$UPDATE_NAME_USAGE"
    exit 1
fi

TARGET_IP="$1"
NEW_NAME="$2"

FIREWALL_DIR="/usr/syno/etc/firewall.d"
SETTINGS_FILE="$FIREWALL_DIR/firewall_settings.json"

PROFILE_NAME=$(grep -o '"profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed -E 's/.*"([^"]*)"/\1/')
echo "$UPDATE_NAME_ACTIVE_PROFILE : $PROFILE_NAME"

# Find the profile file containing the active profile name
PROFILE_FILE=""
for f in "$FIREWALL_DIR"/*.json; do
    # Ignore settings file and backups
    if [ "$f" = "$SETTINGS_FILE" ] || [[ "$f" == *".backup."* ]]; then
        continue
    fi
    
    # Check if this file contains the active profile name
    if grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$PROFILE_NAME\"" "$f"; then
        PROFILE_FILE="$f"
        break
    fi
done

if [ ! -f "$PROFILE_FILE" ]; then
    echo "$UPDATE_NAME_ERROR_PROFILE"
    exit 1
fi

echo "$UPDATE_NAME_PROFILE_FILE : $PROFILE_FILE"

# Validate that the provided IP address exists in the current profile
# Fixed validation to properly check if the IP exists in any rule's ipList
if ! jq --arg ip "$TARGET_IP" '.rules.global[] | select(.ipList | contains([$ip]) or any(. | contains($ip)))' "$PROFILE_FILE" | grep -q .; then
    echo "$(printf "$UPDATE_NAME_IP_NOT_FOUND" "$TARGET_IP")"
    exit 1
fi

# Validate that the new name is not empty
if [ -z "$NEW_NAME" ]; then
    echo "$UPDATE_NAME_EMPTY_NAME"
    exit 1
fi

# Backup
BACKUP_FILE="${PROFILE_FILE}.backup.$(date +%Y%m%d%H%M%S)"
cp "$PROFILE_FILE" "$BACKUP_FILE"
echo "$UPDATE_NAME_BACKUP : $BACKUP_FILE"

# Update with jq
TMP_FILE=$(mktemp)

jq --arg ip "$TARGET_IP" --arg name "$NEW_NAME" '
.rules.global |= map(
  if (.ipList | contains([$ip]) or any(. | contains($ip))) then
    .name = $name
  else
    .
  end
)' "$PROFILE_FILE" > "$TMP_FILE"

# Validate the result
if [ -s "$TMP_FILE" ] && jq empty "$TMP_FILE" 2>/dev/null; then
    cp "$TMP_FILE" "$PROFILE_FILE"
    echo "$(printf "$UPDATE_NAME_SUCCESS" "$TARGET_IP")"
else
    echo "$UPDATE_NAME_ERROR_JSON"
    cp "$BACKUP_FILE" "$PROFILE_FILE"
    exit 1
fi

# Reload the firewall
/usr/syno/bin/synofirewall --reload

rm -f "$TMP_FILE"

# Show updated rules
if [ -x "$SCRIPT_DIR/list_firewall_rules.sh" ]; then
    echo
    echo "$UPDATE_NAME_UPDATED_RULES"
    "$SCRIPT_DIR/list_firewall_rules.sh"
fi