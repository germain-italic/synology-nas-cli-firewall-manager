#!/bin/bash

# manage.sh - CLI interface for Synology firewall management
# This script serves as a homepage for all firewall management scripts

# Colors for better readability
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Path to the directory containing the scripts
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Check privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

# Check required commands
for cmd in jq iptables; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

# Check if synofirewall exists
if [ ! -x "/usr/syno/bin/synofirewall" ]; then
    echo "Error: /usr/syno/bin/synofirewall does not exist or is not executable."
    exit 1
fi

# Load the .env file
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    # Create a default .env file
    cat <<EOL > "$SCRIPT_DIR/.env"
# Default configuration for Synology CLI Firewall Manager

# Language setting (en or fr)
LANG="en"
EOL

    echo -e "${YELLOW}A default .env config file has been created at $SCRIPT_DIR/.env.${NC}"
    echo -e "${YELLOW}The default language is set to LANG=en for English).${NC}"
    echo -e "${YELLOW}Press Enter to reload the script and apply the default settings.${NC}"
    read -p ""
    exec "$0"  # Restart the script
else
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# Load the appropriate language file
if [ "$LANG" = "en" ]; then
    if [ -f "$SCRIPT_DIR/lang/en.sh" ]; then
        source "$SCRIPT_DIR/lang/en.sh"
    else
        echo "Error: English language file not found."
        exit 1
    fi
else
    if [ -f "$SCRIPT_DIR/lang/fr.sh" ]; then
        source "$SCRIPT_DIR/lang/fr.sh"
    else
        echo "Erreur: Fichier de langue français introuvable."
        exit 1
    fi
fi

# Function to display the header
show_header() {
    clear
    echo -e "${BLUE}=================================================================${NC}"
    echo -e "${BLUE}          $TITLE_MAIN                  ${NC}"
    echo -e "${BLUE}=================================================================${NC}"
    echo
}

# Function to display the current firewall status
show_firewall_status() {
    echo -e "${YELLOW}=== $TITLE_CURRENT_STATUS ===${NC}"
    
    # Check if the firewall is enabled - improved method
    if sudo iptables -S | grep -q "INPUT_FIREWALL\|FORWARD_FIREWALL"; then
        echo -e "${STATUS_ACTIVE_PROFILE}: ${GREEN}${STATUS_ENABLED}${NC}"
    else
        echo -e "${STATUS_ACTIVE_PROFILE}: ${RED}${STATUS_DISABLED}${NC}"
    fi
    
    # Check the status in the configuration file
    FIREWALL_DIR="/usr/syno/etc/firewall.d"
    SETTINGS_FILE="$FIREWALL_DIR/firewall_settings.json"
    
    if [ -f "$SETTINGS_FILE" ]; then
        if grep -q '"status"[[:space:]]*:[[:space:]]*true' "$SETTINGS_FILE"; then
            echo -e "${STATUS_CONFIG_STATE}: ${GREEN}${STATUS_ENABLED}${NC}"
        else
            echo -e "${STATUS_CONFIG_STATE}: ${RED}${STATUS_DISABLED}${NC}"
        fi
        
        PROFILE_NAME=$(grep -o '"profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed -E 's/"profile"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/')
        echo -e "${STATUS_ACTIVE_PROFILE}: ${GREEN}$PROFILE_NAME${NC}"
        
        # Find the number of rules
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
        
        if [ -n "$PROFILE_FILE" ] && command -v jq >/dev/null 2>&1; then
            RULE_COUNT=$(jq '.rules.global | length' "$PROFILE_FILE")
            ALLOW_COUNT=$(jq '.rules.global | map(select(.policy == 0)) | length' "$PROFILE_FILE" 2>/dev/null || echo "?")
            DENY_COUNT=$(jq '.rules.global | map(select(.policy == 1)) | length' "$PROFILE_FILE" 2>/dev/null || echo "?")
            echo -e "${STATUS_RULE_COUNT}: ${GREEN}$RULE_COUNT${NC} (${GREEN}$ALLOW_COUNT${NC} ${STATUS_ALLOW}, ${RED}$DENY_COUNT${NC} ${STATUS_DENY})"
        else
            echo -e "${STATUS_RULE_COUNT}: ${YELLOW}${STATUS_UNKNOWN}${NC}"
        fi
    else
        echo -e "${STATUS_ACTIVE_PROFILE}: ${RED}${STATUS_NOT_FOUND}${NC}"
    fi
    
    # Display the number of IPs allowed in iptables
    IP_COUNT=$(sudo iptables -S INPUT_FIREWALL | grep -c " -s .* -j RETURN")
    echo -e "${STATUS_IPS_IN_IPTABLES}: ${GREEN}$IP_COUNT${NC}"
    
    echo
}

# Function to check that all required scripts are present
check_required_scripts() {
    local missing=0
    local required_scripts=("list_firewall_rules.sh" "add_firewall_ip.sh" "remove_firewall_ip.sh" "update_firewall_rule_name.sh" "update_hostname_ip.sh")
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            echo -e "${RED}$(printf "$MANAGE_ERROR_MISSING" "$script")${NC}"
            missing=1
        elif [ ! -x "$SCRIPT_DIR/$script" ]; then
            echo -e "${YELLOW}$(printf "$MANAGE_WARNING_EXEC" "$script")${NC}"
            chmod +x "$SCRIPT_DIR/$script"
        fi
    done
    
    if [ $missing -eq 1 ]; then
        echo -e "${RED}$MANAGE_ERROR_REQUIRED${NC}"
        echo
        echo -e "$MSG_CONTINUE"
        read
    fi
}

# Function to change the language
change_language() {
    echo
    echo -e "${YELLOW}$(printf "$MANAGE_CURRENT_LANGUAGE" "$LANG")${NC}"
    echo -e "1. $MANAGE_ENGLISH"
    echo -e "2. $MANAGE_FRENCH"
    echo
    read -p "$MANAGE_CHOOSE_LANGUAGE " lang_choice
    
    case "$lang_choice" in
        1)
            sed -i 's/^LANG=.*/LANG="en"/' "$SCRIPT_DIR/.env"
            echo "$MANAGE_LANG_ENGLISH"
            ;;
        2)
            sed -i 's/^LANG=.*/LANG="fr"/' "$SCRIPT_DIR/.env"
            echo "$MANAGE_LANG_FRENCH"
            ;;
        *)
            echo "$MANAGE_INVALID_LANG"
            sleep 1
            return
            ;;
    esac
    
    sleep 1
    exec "$0"  # Restart the script
}

# Main function to display the menu
show_menu() {
    show_header
    show_firewall_status
    
    echo -e "${YELLOW}=== $TITLE_AVAILABLE_ACTIONS ===${NC}"
    echo -e "${GREEN}1.${NC} $MENU_LIST_RULES"
    echo -e "${GREEN}2.${NC} $MENU_ADD_IP"
    echo -e "${GREEN}4.${NC} $MENU_UPDATE_NAME"
    echo -e "${GREEN}5.${NC} $MENU_UPDATE_HOSTNAME"
    echo -e "${GREEN}3.${NC} $MENU_REMOVE_RULE"
    echo
    echo -e "${YELLOW}=== $TITLE_ADVANCED_ACTIONS ===${NC}"
    echo -e "${GREEN}6.${NC} $MENU_SHOW_IPTABLES"
    echo -e "${GREEN}7.${NC} $MENU_TOGGLE_FIREWALL"
    echo -e "${GREEN}8.${NC} $MENU_RELOAD_CONFIG"
    echo -e "${GREEN}9.${NC} $MENU_CLEAN_BACKUPS"
    echo
    echo -e "${YELLOW}=== $TITLE_SETTINGS ===${NC}"
    echo -e "${GREEN}u/U.${NC} $MENU_UPDATE_SCRIPTS"
    echo -e "${GREEN}l/L.${NC} $MENU_CHANGE_LANGUAGE"
    echo -e "${RED}q/Q.${NC} $MENU_EXIT"
    echo
    echo -n "$MANAGE_ENTER_CHOICE: "
}

# Function to list firewall rules
list_firewall_rules() {
    "$SCRIPT_DIR/list_firewall_rules.sh"
}

# Function to add an IP to the whitelist
add_ip() {
    echo
    read -p "$MANAGE_ENTER_IP " ip
    read -p "$MANAGE_ENTER_NAME " name
    
    if [ -z "$name" ]; then
        "$SCRIPT_DIR/add_firewall_ip.sh" "$ip"
    else
        "$SCRIPT_DIR/add_firewall_ip.sh" "$ip" "$name"
    fi
}

# Function to remove a rule
remove_rule() {
    echo
    read -p "$MANAGE_ENTER_REMOVE " rule
    
    "$SCRIPT_DIR/remove_firewall_ip.sh" "$rule"
}

# Function to update the name of a rule
update_rule_name() {
    echo
    read -p "$MANAGE_ENTER_IP_UPDATE " ip
    read -p "$MANAGE_ENTER_NEW_NAME " name
    
    "$SCRIPT_DIR/update_firewall_rule_name.sh" "$ip" "$name"
}

# Function to update the IP of a hostname
update_hostname() {
    echo
    read -p "$MANAGE_ENTER_HOSTNAME " hostname
    
    if [ -z "$hostname" ]; then
        "$SCRIPT_DIR/update_hostname_ip.sh"
    else
        "$SCRIPT_DIR/update_hostname_ip.sh" "$hostname"
    fi
}

# Function to display all iptables chains
show_iptables() {
    echo
    echo -e "${YELLOW}=== $MENU_SHOW_IPTABLES ===${NC}"
    sudo iptables -L -v
    echo
    echo -e "$MSG_CONTINUE"
    read
}

# Function to enable/disable the firewall
toggle_firewall() {
    echo
    if sudo iptables -S | grep -q "INPUT_FIREWALL\|FORWARD_FIREWALL"; then
        echo -e "${YELLOW}$MANAGE_FW_ENABLED${NC}"
        read -p "" confirm
        if [[ "$confirm" =~ ^[yY][eE]?[sS]?$ ]] || [[ "$confirm" =~ ^[oO][uU]?[iI]?$ ]]; then
            sudo /usr/syno/bin/synofirewall --disable
            echo -e "${GREEN}$MANAGE_FW_ENABLED_OK${NC}"
        fi
    else
        echo -e "${YELLOW}$MANAGE_FW_DISABLED${NC}"
        read -p "" confirm
        if [[ "$confirm" =~ ^[yY][eE]?[sS]?$ ]] || [[ "$confirm" =~ ^[oO][uU]?[iI]?$ ]]; then
            sudo /usr/syno/bin/synofirewall --enable
            echo -e "${GREEN}$MANAGE_FW_DISABLED_OK${NC}"
        fi
    fi
    
    echo
    echo -e "$MSG_CONTINUE"
    read
}

# Function to reload the firewall configuration
reload_firewall() {
    echo
    echo -e "${YELLOW}$MANAGE_RELOAD_FW${NC}"
    sudo /usr/syno/bin/synofirewall --reload
    echo -e "${GREEN}$MANAGE_RELOAD_COMPLETE${NC}"
    echo
    echo -e "$MSG_CONTINUE"
    read
}

# Function to clean up backup files
clean_backups() {
    echo
    echo -e "${YELLOW}$MANAGE_BACKUP_FILES${NC}"
    ls -la /usr/syno/etc/firewall.d/*.backup.* 2>/dev/null
    echo
    echo -e "${YELLOW}$MANAGE_DELETE_BACKUP${NC}"
    read -p "" confirm
    if [[ "$confirm" =~ ^[yY][eE]?[sS]?$ ]] || [[ "$confirm" =~ ^[oO][uU]?[iI]?$ ]]; then
        sudo rm -f /usr/syno/etc/firewall.d/*.backup.*
        echo -e "${GREEN}$MANAGE_BACKUP_DELETED${NC}"
    fi
    
    echo
    echo -e "$MSG_CONTINUE"
    read
}

# Function to update scripts via git pull
update_scripts() {
    echo
    echo -e "${YELLOW}=== $MENU_UPDATE_SCRIPTS ===${NC}"
    
    if ! command -v git &> /dev/null; then
        echo -e "${RED}$MANAGE_GIT_ERROR${NC}"
        echo
        read -p "$MSG_CONTINUE"
        return
    fi

    CURRENT_DIR=$(pwd)
    cd "$SCRIPT_DIR" || return

    if git rev-parse --is-inside-work-tree &> /dev/null; then
        echo -e "$MANAGE_SCRIPTS_DIR: ${GREEN}$SCRIPT_DIR${NC}"
        
        # Check if it's a submodule (git file is a link to ../../.git/modules/...)
        if [ -f .git ] && grep -q "gitdir:" .git; then
            echo -e "$MANAGE_GIT_SUBMODULE_DETECTED"
            if git pull origin master; then
                echo -e "${GREEN}$MANAGE_SUBMODULE_UPDATED${NC}"
            else
                echo -e "${RED}$MANAGE_SUBMODULE_FAILED${NC}"
            fi
        else
            echo -e "$MANAGE_GIT_STANDALONE"
            if git pull; then
                echo -e "${GREEN}$MANAGE_UPDATE_SUCCESS${NC}"
            else
                echo -e "${RED}$MANAGE_UPDATE_ERROR${NC}"
            fi
        fi

        echo -e "$MANAGE_UPDATE_PERMS"
        chmod +x *.sh
        echo -e "${GREEN}$MANAGE_PERMS_UPDATED${NC}"

        cd "$CURRENT_DIR"
        echo
        read -p "$MSG_CONTINUE" 
        exec "$SCRIPT_DIR/manage.sh"
    else
        echo -e "${RED}$MANAGE_GIT_INVALID${NC}"
        echo
        git status 2>&1 || echo -e "${RED}$MANAGE_GIT_STATUS_ERROR${NC}"
        echo -e "${YELLOW}$MANAGE_MANUAL_UPDATE${NC}"
    fi

    cd "$CURRENT_DIR"
    echo
    read -p "$MSG_CONTINUE"
}

# Check required scripts
check_required_scripts

# Main loop
while true; do
    show_menu
    read choice
    
    case "$choice" in
        q|Q)
            echo -e "${GREEN}$MANAGE_GOODBYE${NC}"
            exit 0
            ;;
        1)
            list_firewall_rules
            echo
            echo -e "$MSG_CONTINUE"
            read
            ;;
        2)
            add_ip
            echo
            echo -e "$MSG_CONTINUE"
            read
            ;;
        3)
            remove_rule
            echo
            echo -e "$MSG_CONTINUE"
            read
            ;;
        4)
            update_rule_name
            echo
            echo -e "$MSG_CONTINUE"
            read
            ;;
        5)
            update_hostname
            echo
            echo -e "$MSG_CONTINUE"
            read
            ;;
        6)
            show_iptables
            ;;
        7)
            toggle_firewall
            ;;
        8)
            reload_firewall
            ;;
        9)
            clean_backups
            ;;
        u|U)
            update_scripts
            ;;
        l|L)
            change_language
            ;;
        *)
            echo -e "${RED}$MANAGE_INVALID_CHOICE${NC}"
            sleep 1
            ;;
    esac
done