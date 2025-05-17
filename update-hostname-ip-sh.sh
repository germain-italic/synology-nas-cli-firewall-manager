#!/bin/bash

# This script checks if the IP associated with a hostname has changed
# and updates the firewall accordingly
# Usage: ./update_hostname_ip.sh [hostname]

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

# Configuration
DEFAULT_HOSTNAME="myhome.ddns.net"
HOSTNAME=${1:-$DEFAULT_HOSTNAME}  # Use the parameter if provided, otherwise the default value

# Use a history file specific to each hostname
# and store it in a more permanent location
HISTORY_DIR="/volume1/homes/$(whoami)/firewall_history"
IP_HISTORY_FILE="$HISTORY_DIR/${HOSTNAME//./_}.history"  # Replace dots with underscores

# Add a timestamp at the beginning of execution
echo "======================================================"
echo "$(printf "$UPDATE_HOST_EXECUTION" "$(date +'%Y-%m-%d %H:%M:%S')")"
echo "======================================================"

# Create the history directory if it doesn't exist
if [ ! -d "$HISTORY_DIR" ]; then
    echo "$(printf "$UPDATE_HOST_CREATE_DIR" "$HISTORY_DIR")"
    mkdir -p "$HISTORY_DIR"
    chmod 700 "$HISTORY_DIR"  # Secure the directory
fi

# Check if the add and remove scripts are present
if [ ! -f "$SCRIPT_DIR/add_firewall_ip.sh" ] || [ ! -f "$SCRIPT_DIR/remove_firewall_ip.sh" ]; then
    echo "$UPDATE_HOST_ERROR_SCRIPTS"
    exit 1
fi

# Make the scripts executable if necessary
chmod +x "$SCRIPT_DIR/add_firewall_ip.sh" "$SCRIPT_DIR/remove_firewall_ip.sh"

# Get the current IP address associated with the hostname
echo "$(printf "$UPDATE_HOST_RESOLVING" "$HOSTNAME")"
CURRENT_IP=""

# Try several DNS resolution methods
# 1. Ping method (works on most systems)
if [ -z "$CURRENT_IP" ]; then
    CURRENT_IP=$(ping -c 1 $HOSTNAME 2>/dev/null | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
fi

# 2. Host method
if [ -z "$CURRENT_IP" ] && command -v host >/dev/null 2>&1; then
    CURRENT_IP=$(host $HOSTNAME 2>/dev/null | grep 'has address' | awk '{print $4}')
fi

# 3. Nslookup method
if [ -z "$CURRENT_IP" ] && command -v nslookup >/dev/null 2>&1; then
    CURRENT_IP=$(nslookup $HOSTNAME 2>/dev/null | grep -A1 'Name:' | grep 'Address:' | tail -1 | awk '{print $2}')
fi

# 4. Dig method (unlikely on Synology but we keep it just in case)
if [ -z "$CURRENT_IP" ] && command -v dig >/dev/null 2>&1; then
    CURRENT_IP=$(dig +short $HOSTNAME)
fi

# 5. Getent method (available on some Linux systems)
if [ -z "$CURRENT_IP" ] && command -v getent >/dev/null 2>&1; then
    CURRENT_IP=$(getent hosts $HOSTNAME | awk '{print $1}')
fi

if [ -z "$CURRENT_IP" ]; then
    echo "$(printf "$UPDATE_HOST_ERROR_RESOLVE" "$HOSTNAME")"
    exit 1
fi

echo "$(printf "$UPDATE_HOST_CURRENT_IP" "$HOSTNAME" "$CURRENT_IP")"

# Create the history file if it doesn't exist
if [ ! -f "$IP_HISTORY_FILE" ]; then
    echo "$(printf "$UPDATE_HOST_CREATE_HISTORY" "$HOSTNAME")"
    echo "# Historique des IPs pour $HOSTNAME" > "$IP_HISTORY_FILE"
    echo "# Format: DATE IP" >> "$IP_HISTORY_FILE"
    echo "LAST_IP=" >> "$IP_HISTORY_FILE"
fi

# Read the last known IP
LAST_IP=$(grep -E "^LAST_IP=" "$IP_HISTORY_FILE" | cut -d'=' -f2)

echo "$(printf "$UPDATE_HOST_LAST_IP" "$HOSTNAME" "$LAST_IP")"
echo "$(printf "$UPDATE_HOST_HISTORY_STORED" "$IP_HISTORY_FILE")"

# If the IP has changed
if [ "$CURRENT_IP" != "$LAST_IP" ]; then
    echo "$(printf "$UPDATE_HOST_IP_CHANGED" "$LAST_IP" "$CURRENT_IP")"
    
    # If a previous IP exists, remove it from the firewall
    if [ -n "$LAST_IP" ]; then
        echo "$(printf "$UPDATE_HOST_REMOVING_OLD" "$HOSTNAME")"
        "$SCRIPT_DIR/remove_firewall_ip.sh" "$HOSTNAME"
    fi
    
    # Add the new IP
    echo "$(printf "$UPDATE_HOST_ADDING_NEW" "$CURRENT_IP" "$HOSTNAME")"
    "$SCRIPT_DIR/add_firewall_ip.sh" "$CURRENT_IP" "$HOSTNAME"
    
    # Update the history
    sed -i "s/^LAST_IP=.*/LAST_IP=$CURRENT_IP/" "$IP_HISTORY_FILE"
    echo "$(date +'%Y-%m-%d %H:%M:%S') $CURRENT_IP" >> "$IP_HISTORY_FILE"
    
    echo "$UPDATE_HOST_UPDATE_SUCCESS"    
else
    echo "$UPDATE_HOST_NO_CHANGE"
fi