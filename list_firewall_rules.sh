#!/bin/bash

# Load configuration and language files
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    # Default language if config doesn't exist
    LANG="en"
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

FIREWALL_DIR="/usr/syno/etc/firewall.d"
SETTINGS_FILE="$FIREWALL_DIR/firewall_settings.json"

# Determine the active profile
PROFILE_NAME=$(grep -o '"profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed -E 's/"profile"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/')
echo "$LIST_ACTIVE_PROFILE: $PROFILE_NAME"

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

if [ -z "$PROFILE_FILE" ]; then
    echo "$(printf "$LIST_NO_PROFILE" "$PROFILE_NAME")"
    exit 1
fi

echo "$LIST_PROFILE_FILE: $PROFILE_FILE"
echo "---------------------------------------------------------------------------------------------"
printf "| %-34s | %-38s | %-7s |\n" "Rule Name" "IP Address(es)" "Enabled"
echo "---------------------------------------------------------------------------------------------"

if command -v jq >/dev/null 2>&1; then
    jq -r '
      .rules.global[]
      | select(.ipList | type == "array" and length > 0)
      | [(if (.name | tostring | length) > 0 then .name else "-" end), (.ipList | join(", ")), (.enable // false)]
      | @tsv
    ' "$PROFILE_FILE" | while IFS=$'\t' read -r name iplist enabled; do
        printf "| %-34s | %-38s | %-7s |\n" "$name" "$iplist" "$enabled"
    done
else
    echo "$LIST_JQ_UNAVAILABLE"
    
    # Simple alternative if jq isn't available
    echo "$LIST_RAW_CONTENT"
    grep -A 20 '"ipList"' "$PROFILE_FILE" | grep -B 20 '"table"' | sed 's/^/  /'
fi

echo "---------------------------------------------------------------------------------------------"