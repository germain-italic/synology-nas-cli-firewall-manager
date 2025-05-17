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

# Rotation of the main log file
LOG_FILE="/var/log/update_noip.log"
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 1048576 ]; then
    echo "$(printf "$ROTATE_MAIN_LOG" "$LOG_FILE")"
    mv "$LOG_FILE" "${LOG_FILE}.1"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
fi

# Rotation of history files by hostname
HISTORY_DIR="/volume1/homes/$(whoami)/firewall_history"
MAX_SIZE=1048576  # 1MB

# Check if history directory exists
if [ -d "$HISTORY_DIR" ]; then
    echo "$(printf "$ROTATE_CHECK_DIR" "$HISTORY_DIR")"
    
    # Loop through all history files
    for history_file in "$HISTORY_DIR"/*.history; do
        if [ -f "$history_file" ]; then
            # Extract important information from the file
            hostname_line=$(grep "^# Historique des IPs pour" "$history_file" | head -1)
            last_ip=$(grep "^LAST_IP=" "$history_file" | cut -d'=' -f2)
            
            # Check file size
            file_size=$(stat -c%s "$history_file")
            if [ "$file_size" -gt "$MAX_SIZE" ]; then
                echo "$(printf "$ROTATE_HISTORY_FILE" "$history_file")"
                
                # Create a backup file
                backup_file="${history_file}.$(date +%Y%m%d)"
                
                # If backup file already exists, add a number
                counter=1
                while [ -f "$backup_file" ]; do
                    backup_file="${history_file}.$(date +%Y%m%d).$counter"
                    counter=$((counter + 1))
                done
                
                # Do the rotation
                cp "$history_file" "$backup_file"
                
                # Recreate a new file with only essential information
                echo "$hostname_line" > "$history_file"
                echo "# Format: DATE IP" >> "$history_file"
                echo "LAST_IP=$last_ip" >> "$history_file"
                
                # Add the last 10 entries for reference
                tail -10 "$backup_file" | grep -v "^#" | grep -v "^LAST_IP=" >> "$history_file"
                
                echo "$(printf "$ROTATE_COMPLETE" "$history_file" "$backup_file")"
            fi
        fi
    done
else
    echo "$(printf "$ROTATE_DIR_NOT_FOUND" "$HISTORY_DIR")"
fi