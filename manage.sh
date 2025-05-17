#!/bin/bash

# manage.sh - Interface CLI pour la gestion du firewall Synology
# Ce script sert de page d'accueil pour tous les scripts de gestion du firewall

# Couleurs pour améliorer la lisibilité
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Chemin du répertoire contenant les scripts
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Fonction pour afficher l'en-tête
show_header() {
    clear
    echo -e "${BLUE}=================================================================${NC}"
    echo -e "${BLUE}          GESTIONNAIRE DE FIREWALL SYNOLOGY DSM                  ${NC}"
    echo -e "${BLUE}=================================================================${NC}"
    echo
}

# Fonction pour afficher le statut actuel du firewall
show_firewall_status() {
    echo -e "${YELLOW}=== STATUT ACTUEL DU FIREWALL ===${NC}"
    
    # Vérifier si le firewall est activé - méthode améliorée
    if sudo iptables -S | grep -q "INPUT_FIREWALL\|FORWARD_FIREWALL"; then
        echo -e "État du firewall: ${GREEN}ACTIVÉ${NC}"
    else
        echo -e "État du firewall: ${RED}DÉSACTIVÉ${NC}"
    fi
    
    # Vérifier le statut dans le fichier de configuration
    FIREWALL_DIR="/usr/syno/etc/firewall.d"
    SETTINGS_FILE="$FIREWALL_DIR/firewall_settings.json"
    
    if [ -f "$SETTINGS_FILE" ]; then
        if grep -q '"status"[[:space:]]*:[[:space:]]*true' "$SETTINGS_FILE"; then
            echo -e "État dans la configuration: ${GREEN}ACTIVÉ${NC}"
        else
            echo -e "État dans la configuration: ${RED}DÉSACTIVÉ${NC}"
        fi
        
        PROFILE_NAME=$(grep -o '"profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed -E 's/"profile"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/')
        echo -e "Profil actif: ${GREEN}$PROFILE_NAME${NC}"
        
        # Trouver le nombre de règles
        PROFILE_FILE=""
        for f in "$FIREWALL_DIR"/*.json; do
            # Ignorer le fichier de settings et les backups
            if [ "$f" = "$SETTINGS_FILE" ] || [[ "$f" == *".backup."* ]]; then
                continue
            fi
            
            # Vérifier si ce fichier contient le nom du profil actif
            if grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$PROFILE_NAME\"" "$f"; then
                PROFILE_FILE="$f"
                break
            fi
        done
        
        if [ -n "$PROFILE_FILE" ] && command -v jq >/dev/null 2>&1; then
            RULE_COUNT=$(jq '.rules.global | length' "$PROFILE_FILE")
            ALLOW_COUNT=$(jq '.rules.global | map(select(.policy == 0)) | length' "$PROFILE_FILE" 2>/dev/null || echo "?")
            DENY_COUNT=$(jq '.rules.global | map(select(.policy == 1)) | length' "$PROFILE_FILE" 2>/dev/null || echo "?")
            echo -e "Nombre de règles: ${GREEN}$RULE_COUNT${NC} (${GREEN}$ALLOW_COUNT${NC} autorisations, ${RED}$DENY_COUNT${NC} refus)"
        else
            echo -e "Nombre de règles: ${YELLOW}Inconnu (jq non disponible)${NC}"
        fi
    else
        echo -e "Profil actif: ${RED}Introuvable${NC}"
    fi
    
    # Afficher le nombre d'IPs autorisées dans iptables
    IP_COUNT=$(sudo iptables -S INPUT_FIREWALL | grep -c " -s .* -j RETURN")
    echo -e "IPs autorisées dans iptables: ${GREEN}$IP_COUNT${NC}"
    
    echo
}

# Fonction pour vérifier que tous les scripts requis sont présents
check_required_scripts() {
    local missing=0
    local required_scripts=("list_firewall_rules.sh" "add_firewall_ip.sh" "remove_firewall_ip.sh" "update_firewall_rule_name.sh" "update_hostname_ip.sh")
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            echo -e "${RED}ERREUR: Le script $script est manquant!${NC}"
            missing=1
        elif [ ! -x "$SCRIPT_DIR/$script" ]; then
            echo -e "${YELLOW}ATTENTION: Le script $script n'est pas exécutable. Correction automatique...${NC}"
            chmod +x "$SCRIPT_DIR/$script"
        fi
    done
    
    if [ $missing -eq 1 ]; then
        echo -e "${RED}Certains scripts nécessaires sont manquants. Vérifiez votre installation.${NC}"
        echo
        echo -e "Appuyez sur Entrée pour continuer..."
        read
    fi
}

# Fonction principale pour afficher le menu
show_menu() {
    show_header
    show_firewall_status
    
    echo -e "${YELLOW}=== ACTIONS DISPONIBLES ===${NC}"
    echo -e "${GREEN}1.${NC} Lister les règles du firewall"
    echo -e "${GREEN}2.${NC} Ajouter une IP à la whitelist"
    echo -e "${GREEN}3.${NC} Supprimer une règle (par nom ou IP)"
    echo -e "${GREEN}4.${NC} Mettre à jour le nom d'une règle"
    echo -e "${GREEN}5.${NC} Mettre à jour l'IP d'un hostname (DDNS)"
    echo
    echo -e "${YELLOW}=== ACTIONS AVANCÉES ===${NC}"
    echo -e "${GREEN}6.${NC} Afficher toutes les chaînes iptables"
    echo -e "${GREEN}7.${NC} Activer/Désactiver le firewall"
    echo -e "${GREEN}8.${NC} Recharger la configuration du firewall"
    echo -e "${GREEN}9.${NC} Nettoyer les fichiers de sauvegarde"
    echo -e "${GREEN}10.${NC} Mettre à jour les scripts (git pull)"
    echo
    echo -e "${RED}q/Q.${NC} Quitter"
    echo
    echo -n "Votre choix: "
}

# Fonction pour lister les règles du firewall
list_firewall_rules() {
    "$SCRIPT_DIR/list_firewall_rules.sh"
}

# Fonction pour ajouter une IP à la whitelist
add_ip() {
    echo
    read -p "Entrez l'adresse IP à ajouter: " ip
    read -p "Entrez un nom pour cette règle (ou laissez vide pour utiliser l'IP): " name
    
    if [ -z "$name" ]; then
        "$SCRIPT_DIR/add_firewall_ip.sh" "$ip"
    else
        "$SCRIPT_DIR/add_firewall_ip.sh" "$ip" "$name"
    fi
}

# Fonction pour supprimer une règle
remove_rule() {
    echo
    read -p "Entrez le nom de la règle ou l'IP à supprimer: " rule
    
    "$SCRIPT_DIR/remove_firewall_ip.sh" "$rule"
}

# Fonction pour mettre à jour le nom d'une règle
update_rule_name() {
    echo
    read -p "Entrez l'adresse IP dont vous voulez modifier le nom: " ip
    read -p "Entrez le nouveau nom pour cette règle: " name
    
    "$SCRIPT_DIR/update_firewall_rule_name.sh" "$ip" "$name"
}

# Fonction pour mettre à jour l'IP d'un hostname
update_hostname() {
    echo
    read -p "Entrez le hostname à mettre à jour (ou laissez vide pour défaut): " hostname
    
    if [ -z "$hostname" ]; then
        "$SCRIPT_DIR/update_hostname_ip.sh"
    else
        "$SCRIPT_DIR/update_hostname_ip.sh" "$hostname"
    fi
}

# Fonction pour afficher toutes les chaînes iptables
show_iptables() {
    echo
    echo -e "${YELLOW}=== RÈGLES IPTABLES ACTUELLES ===${NC}"
    sudo iptables -L -v
    echo
    echo -e "Appuyez sur Entrée pour continuer..."
    read
}

# Fonction pour activer/désactiver le firewall
toggle_firewall() {
    echo
    if sudo iptables -S | grep -q "INPUT_FIREWALL\|FORWARD_FIREWALL"; then
        echo -e "${YELLOW}Le firewall est actuellement ACTIVÉ. Voulez-vous le désactiver? (o/N)${NC}"
        read -p "" confirm
        if [[ "$confirm" =~ ^[oO][uU]?[iI]?$ ]]; then
            sudo /usr/syno/bin/synofirewall --disable
            echo -e "${GREEN}Le firewall a été désactivé.${NC}"
        fi
    else
        echo -e "${YELLOW}Le firewall est actuellement DÉSACTIVÉ. Voulez-vous l'activer? (o/N)${NC}"
        read -p "" confirm
        if [[ "$confirm" =~ ^[oO][uU]?[iI]?$ ]]; then
            sudo /usr/syno/bin/synofirewall --enable
            echo -e "${GREEN}Le firewall a été activé.${NC}"
        fi
    fi
    
    echo
    echo -e "Appuyez sur Entrée pour continuer..."
    read
}

# Fonction pour recharger la configuration du firewall
reload_firewall() {
    echo
    echo -e "${YELLOW}Rechargement de la configuration du firewall...${NC}"
    sudo /usr/syno/bin/synofirewall --reload
    echo -e "${GREEN}Configuration rechargée.${NC}"
    echo
    echo -e "Appuyez sur Entrée pour continuer..."
    read
}

# Fonction pour nettoyer les fichiers de sauvegarde
clean_backups() {
    echo
    echo -e "${YELLOW}Fichiers de sauvegarde dans /usr/syno/etc/firewall.d/:${NC}"
    ls -la /usr/syno/etc/firewall.d/*.backup.* 2>/dev/null
    echo
    echo -e "${YELLOW}Voulez-vous supprimer tous ces fichiers de sauvegarde? (o/N)${NC}"
    read -p "" confirm
    if [[ "$confirm" =~ ^[oO][uU]?[iI]?$ ]]; then
        sudo rm -f /usr/syno/etc/firewall.d/*.backup.*
        echo -e "${GREEN}Fichiers de sauvegarde supprimés.${NC}"
    fi
    
    echo
    echo -e "Appuyez sur Entrée pour continuer..."
    read
}

# Fonction pour mettre à jour les scripts via git pull
update_scripts() {
    echo
    echo -e "${YELLOW}=== MISE À JOUR DES SCRIPTS ===${NC}"
    
    # Vérifier si git est disponible
    if ! command -v git &> /dev/null; then
        echo -e "${RED}Git n'est pas installé ou n'est pas dans le PATH.${NC}"
        echo
        echo -e "Appuyez sur Entrée pour continuer..."
        read
        return
    fi
    
    # Sauvegarde du répertoire courant
    CURRENT_DIR=$(pwd)
    
    # Aller dans le répertoire des scripts
    cd "$SCRIPT_DIR"
    
    # Vérifier si le répertoire est un dépôt git (méthode plus fiable)
    if git rev-parse --is-inside-work-tree &> /dev/null; then
        echo -e "Répertoire de scripts: ${GREEN}$SCRIPT_DIR${NC}"
        echo -e "Exécution de 'git pull' pour mettre à jour les scripts..."
        
        # Vérifier l'état avant le pull
        BEFORE_PULL=$(git rev-parse HEAD)
        
        # Exécuter git pull
        if git pull; then
            # Vérifier l'état après le pull
            AFTER_PULL=$(git rev-parse HEAD)
            
            # Vérifier si des mises à jour ont été appliquées
            if [ "$BEFORE_PULL" != "$AFTER_PULL" ]; then
                echo -e "${GREEN}Scripts mis à jour avec succès!${NC}"
                
                # Rendre tous les scripts exécutables
                echo -e "Mise à jour des permissions..."
                chmod +x *.sh
                echo -e "${GREEN}Permissions mises à jour.${NC}"
                
                echo -e "${YELLOW}Des mises à jour ont été appliquées. Redémarrage du script...${NC}"
                
                # Retourner au répertoire d'origine
                cd "$CURRENT_DIR"
                
                echo
                echo -e "Appuyez sur Entrée pour redémarrer le script..."
                read
                
                # Relancer le script
                exec "$SCRIPT_DIR/manage.sh"
                # La commande exec remplace le processus actuel, donc le code après cette ligne ne sera pas exécuté
            else
                echo -e "${GREEN}Aucune mise à jour disponible. Vous utilisez déjà la dernière version.${NC}"
            fi
        else
            echo -e "${RED}Erreur lors de la mise à jour des scripts.${NC}"
        fi
    else
        echo -e "${RED}Le répertoire n'est pas un dépôt git valide.${NC}"
        echo -e "${YELLOW}État de git dans ce répertoire:${NC}"
        git status 2>&1 || echo -e "${RED}Impossible d'obtenir le statut git.${NC}"
        echo -e "${YELLOW}Pour utiliser cette fonction, le répertoire contenant les scripts doit être cloné depuis un dépôt git.${NC}"
        echo -e "${YELLOW}Si ce n'est pas le cas, vous devrez mettre à jour les scripts manuellement.${NC}"
    fi
    
    # Retourner au répertoire d'origine (seulement si exec n'a pas été appelé)
    cd "$CURRENT_DIR"
    
    echo
    echo -e "Appuyez sur Entrée pour continuer..."
    read
}

# Vérifier les scripts requis
check_required_scripts

# Boucle principale
while true; do
    show_menu
    read choice
    
    case "$choice" in
        q|Q)
            echo -e "${GREEN}Au revoir!${NC}"
            exit 0
            ;;
        0)
            echo -e "${GREEN}Au revoir!${NC}"
            exit 0
            ;;
        1)
            list_firewall_rules
            echo
            echo -e "Appuyez sur Entrée pour continuer..."
            read
            ;;
        2)
            add_ip
            echo
            echo -e "Appuyez sur Entrée pour continuer..."
            read
            ;;
        3)
            remove_rule
            echo
            echo -e "Appuyez sur Entrée pour continuer..."
            read
            ;;
        4)
            update_rule_name
            echo
            echo -e "Appuyez sur Entrée pour continuer..."
            read
            ;;
        5)
            update_hostname
            echo
            echo -e "Appuyez sur Entrée pour continuer..."
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
        10)
            update_scripts
            ;;
        *)
            echo -e "${RED}Choix invalide. Veuillez réessayer.${NC}"
            sleep 1
            ;;
    esac
done