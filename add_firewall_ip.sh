#!/bin/bash

# This script adds an IP address to the Synology DSM 7.x firewall whitelist
# Usage: ./add_firewall_ip.sh <ip_address> [hostname]
# If no hostname is provided, the IP address is used as the rule name

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

# Check if at least one IP address was provided
if [ $# -lt 1 ]; then
    echo "$ADD_USAGE"
    echo "$ADD_EXAMPLE"
    exit 1
fi

# IP address to add
IP_TO_ADD="$1"

# Use provided hostname or default to the IP address as the rule name
if [ $# -gt 1 ]; then
    RULE_NAME="$2"
else
    RULE_NAME="$IP_TO_ADD"
    echo "$ADD_NO_HOSTNAME"
fi

# Check IP format (basic validation)
if ! [[ $IP_TO_ADD =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "$ADD_INVALID_IP"
    exit 1
fi

# Ensure each octet is within the valid range (0-255)
IFS='.' read -r -a octets <<< "$IP_TO_ADD"
for octet in "${octets[@]}"; do
    if ((octet < 0 || octet > 255)); then
        echo "$ADD_INVALID_IP_RANGE"
        exit 1
    fi
done

# Path to firewall configuration files
FIREWALL_DIR="/usr/syno/etc/firewall.d"

# Get the active profile
SETTINGS_FILE="$FIREWALL_DIR/firewall_settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "$ADD_ERROR_SETTINGS"
    exit 1
fi

# Determine the active profile
PROFILE_NAME=$(grep -o '"profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed -E 's/"profile"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/')
echo "$ADD_ACTIVE_PROFILE: $PROFILE_NAME"

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
    echo "$ADD_ERROR_PROFILE"
    exit 1
fi

echo "$ADD_PROFILE_MODIFY: $PROFILE_FILE"

# Make a backup of the file
BACKUP_FILE="${PROFILE_FILE}.backup.$(date +%Y%m%d%H%M%S)"
cp "$PROFILE_FILE" "$BACKUP_FILE"
echo "$ADD_BACKUP_CREATED: $BACKUP_FILE"

# Check if rule name already exists in the file
if grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$RULE_NAME\"" "$PROFILE_FILE"; then
    echo "$(printf "$ADD_RULE_EXISTS" "$RULE_NAME")"
    echo "$ADD_USE_REMOVE"
    exit 0
fi

# Check if the IP already exists in iptables rules
if iptables -S | grep -q "$IP_TO_ADD"; then
    echo "$(printf "$ADD_IP_EXISTS" "$IP_TO_ADD")"
fi

# Check the JSON structure and identify the deny rule index
if command -v jq >/dev/null 2>&1; then
    # Check if the file is valid JSON
    if ! jq empty "$PROFILE_FILE" 2>/dev/null; then
        echo "$ADD_ERROR_JSON"
        exit 1
    fi
    
    # Find the index of the deny rule (policy=1)
    DENY_INDEX=$(jq '.rules.global | map(.policy) | index(1)' "$PROFILE_FILE")
    
    if [ "$DENY_INDEX" = "null" ] || [ -z "$DENY_INDEX" ]; then
        echo "$ADD_NO_DENY"
        DENY_INDEX=$(jq '.rules.global | length' "$PROFILE_FILE")
    fi
    
    echo "$ADD_DENY_POSITION: $DENY_INDEX"
    
    # Create a temporary file
    TMP_FILE=$(mktemp)
    
    # Create the new rule and insert it before the deny rule
    jq --arg ip "$IP_TO_ADD" --arg name "$RULE_NAME" --argjson pos "$DENY_INDEX" '
    .rules.global = .rules.global[0:$pos] + [
      {
        "adapterDirect": 1,
        "blLog": false,
        "chainList": ["FORWARD_FIREWALL", "INPUT_FIREWALL"],
        "enable": true,
        "ipDirect": 1,
        "ipGroup": 0,
        "ipList": [$ip],
        "ipType": 0,
        "labelList": [],
        "name": $name,
        "policy": 0,
        "portDirect": 0,
        "portGroup": 3,
        "portList": [],
        "protocol": 3,
        "ruleIndex": (.rules.global | map(.ruleIndex) | max + 1),
        "table": "filter"
      }
    ] + .rules.global[$pos:]
    ' "$PROFILE_FILE" > "$TMP_FILE"
    
    # Check that the temporary file is valid and not empty
    if [ -s "$TMP_FILE" ] && jq empty "$TMP_FILE" 2>/dev/null; then
        echo "$ADD_MOD_SUCCESS"
        cp "$TMP_FILE" "$PROFILE_FILE"
        rm -f "$TMP_FILE"
    else
        echo "$ADD_ERROR_MODIFY"
        rm -f "$TMP_FILE"
        exit 1
    fi
else
    echo "$ADD_JQ_UNAVAILABLE"
    exit 1
fi

# Reload the firewall
echo "$ADD_RELOAD"
if ! /usr/syno/bin/synofirewall --reload; then
    echo "$ADD_RELOAD_ERROR"
    echo "$ADD_RESTORE"
    cp "$BACKUP_FILE" "$PROFILE_FILE"
    /usr/syno/bin/synofirewall --reload
    echo "$ADD_BACKUP_RESTORED"
    exit 1
fi

echo "$(printf "$ADD_IP_ADDED" "$IP_TO_ADD" "$RULE_NAME")"

# Verify that the IP is present in iptables rules
if iptables -S | grep -q "$IP_TO_ADD"; then
    echo "$ADD_VERIFY_SUCCESS"
else
    echo "$ADD_VERIFY_FAIL"
fi

# Verify that the rule name is in the configuration file
if grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$RULE_NAME\"" "$PROFILE_FILE"; then
    echo "$ADD_NAME_SUCCESS"
else
    echo "$ADD_NAME_FAIL"
fi