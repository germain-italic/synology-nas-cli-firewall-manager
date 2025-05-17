#!/bin/bash

# This script removes a rule from the Synology DSM 7.x firewall based on the rule name
# Usage: ./remove_firewall_ip.sh <rule_name>
# The rule_name can be a hostname or an IP address (depending on what was used when adding)

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

# Check if a rule name was provided
if [ $# -ne 1 ]; then
    echo "$REMOVE_USAGE"
    echo "$REMOVE_EXAMPLE"
    exit 1
fi

# Rule name to remove (can be a hostname or an IP address)
RULE_NAME="$1"

# Prevent removal of rules with an empty name
if [ -z "$RULE_NAME" ]; then
    echo "$REMOVE_EMPTY_RULE_NAME"
    exit 1
fi

# Path to firewall configuration files
FIREWALL_DIR="/usr/syno/etc/firewall.d"

# Get the active profile
SETTINGS_FILE="$FIREWALL_DIR/firewall_settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "$REMOVE_ERROR_SETTINGS"
    exit 1
fi

# Determine the active profile
PROFILE_NAME=$(grep -o '"profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed -E 's/"profile"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/')
echo "$REMOVE_ACTIVE_PROFILE: $PROFILE_NAME"

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

if [ -z "$PROFILE_FILE" ] || [ ! -f "$PROFILE_FILE" ]; then
    echo "$REMOVE_ERROR_PROFILE"
    exit 1
fi

echo "$REMOVE_PROFILE_MODIFY: $PROFILE_FILE"

# Make a backup of the file
BACKUP_FILE="${PROFILE_FILE}.backup.$(date +%Y%m%d%H%M%S)"
cp "$PROFILE_FILE" "$BACKUP_FILE"
echo "$REMOVE_BACKUP_CREATED: $BACKUP_FILE"

# Check if rule name exists in the file
if ! grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$RULE_NAME\"" "$PROFILE_FILE"; then
    echo "$(printf "$REMOVE_RULE_NOT_FOUND" "$RULE_NAME")"
    
    # Check if RULE_NAME is an IP address that might be in iptables rules
    if [[ $RULE_NAME =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        if iptables -S | grep -q "$RULE_NAME"; then
            echo "$(printf "$REMOVE_IP_IPTABLES" "$RULE_NAME")"
            echo "$REMOVE_IP_REMOVE"
            iptables -t filter -D FORWARD_FIREWALL -s "$RULE_NAME" -j RETURN 2>/dev/null
            iptables -t filter -D INPUT_FIREWALL -s "$RULE_NAME" -j RETURN 2>/dev/null
            echo "$REMOVE_IP_REMOVED"
            exit 0
        fi
    fi
    
    echo "$REMOVE_NO_ACTION"
    exit 0
fi

# Extract the IP address associated with the rule name to remove it from iptables rules
IP_ADDRESS=""
if command -v jq >/dev/null 2>&1; then
    IP_ADDRESS=$(jq -r --arg name "$RULE_NAME" '.rules.global[] | select(.name == $name) | .ipList[0]' "$PROFILE_FILE")
    
    if [ -n "$IP_ADDRESS" ]; then
        echo "$(printf "$REMOVE_IP_ASSOCIATED" "$RULE_NAME" "$IP_ADDRESS")"
    else
        echo "$(printf "$REMOVE_IP_UNKNOWN" "$RULE_NAME")"
    fi
    
    # Remove the rule with the specified name
    TMP_FILE=$(mktemp)
    
    jq --arg name "$RULE_NAME" '
    .rules.global = (.rules.global | map(
        select(.name != $name)
    ))
    ' "$PROFILE_FILE" > "$TMP_FILE"
    
    # Check that the temporary file is valid and not empty
    if [ -s "$TMP_FILE" ] && jq empty "$TMP_FILE" 2>/dev/null; then
        echo "$REMOVE_MOD_SUCCESS"
        cp "$TMP_FILE" "$PROFILE_FILE"
        rm -f "$TMP_FILE"
    else
        echo "$REMOVE_ERROR_MODIFY"
        rm -f "$TMP_FILE"
        exit 1
    fi
else
    echo "$REMOVE_JQ_UNAVAILABLE"
    exit 1
fi

# If an IP address was found, remove it from iptables rules
if [ -n "$IP_ADDRESS" ]; then
    echo "$(printf "$REMOVE_REMOVE_IPTABLES" "$IP_ADDRESS")"
    iptables -t filter -D FORWARD_FIREWALL -s "$IP_ADDRESS" -j RETURN 2>/dev/null
    iptables -t filter -D INPUT_FIREWALL -s "$IP_ADDRESS" -j RETURN 2>/dev/null
fi

# Reload the firewall
echo "$REMOVE_RELOAD"
if ! /usr/syno/bin/synofirewall --reload; then
    echo "$REMOVE_RELOAD_ERROR"
    echo "$REMOVE_RESTORE"
    cp "$BACKUP_FILE" "$PROFILE_FILE"
    /usr/syno/bin/synofirewall --reload
    echo "$REMOVE_BACKUP_RESTORED"
    exit 1
fi

echo "$(printf "$REMOVE_RULE_REMOVED" "$RULE_NAME")"

# Verify that the rule name has been removed
if grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$RULE_NAME\"" "$PROFILE_FILE"; then
    echo "$REMOVE_VERIFY_FAIL"
else
    echo "$REMOVE_VERIFY_SUCCESS"
fi

# Verify that the IP has been removed from iptables rules, if it was known
if [ -n "$IP_ADDRESS" ] && iptables -S | grep -q "$IP_ADDRESS"; then
    echo "$REMOVE_IP_VERIFY_FAIL"
else
    echo "$REMOVE_IP_VERIFY_SUCCESS"
fi