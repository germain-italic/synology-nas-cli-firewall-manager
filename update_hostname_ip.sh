#!/bin/bash

# Ce script vérifie si l'IP associée à un hostname a changé
# et met à jour le firewall en conséquence
# Usage: ./update_hostname_ip.sh [hostname]

# Configuration
DEFAULT_HOSTNAME="myhome.ddns.net"
HOSTNAME=${1:-$DEFAULT_HOSTNAME}  # Utilise le paramètre s'il est fourni, sinon la valeur par défaut

# Utiliser un fichier d'historique spécifique à chaque hostname
# et le stocker dans un répertoire plus permanent
HISTORY_DIR="/volume1/homes/$(whoami)/firewall_history"
IP_HISTORY_FILE="$HISTORY_DIR/${HOSTNAME//./_}.history"  # Remplacer les points par des underscores

SCRIPT_DIR="$(dirname "$0")"

# Ajouter un timestamp au début de l'exécution
echo "======================================================"
echo "Exécution du $(date +'%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# Créer le répertoire d'historique s'il n'existe pas
if [ ! -d "$HISTORY_DIR" ]; then
    echo "Création du répertoire d'historique $HISTORY_DIR..."
    mkdir -p "$HISTORY_DIR"
    chmod 700 "$HISTORY_DIR"  # Sécuriser le répertoire
fi

# Vérifier si le script d'ajout et de suppression sont présents
if [ ! -f "$SCRIPT_DIR/add_firewall_ip.sh" ] || [ ! -f "$SCRIPT_DIR/remove_firewall_ip.sh" ]; then
    echo "Erreur: Les scripts add_firewall_ip.sh et remove_firewall_ip.sh doivent être dans le même répertoire"
    exit 1
fi

# Rendre les scripts exécutables si nécessaire
chmod +x "$SCRIPT_DIR/add_firewall_ip.sh" "$SCRIPT_DIR/remove_firewall_ip.sh"

# Obtenir l'adresse IP actuelle associée au hostname
echo "Résolution du hostname $HOSTNAME..."
CURRENT_IP=""


# Essayer plusieurs méthodes de résolution DNS
# 1. Méthode ping (fonctionne sur la plupart des systèmes)
if [ -z "$CURRENT_IP" ]; then
    CURRENT_IP=$(ping -c 1 $HOSTNAME 2>/dev/null | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
fi

# 2. Méthode host
if [ -z "$CURRENT_IP" ] && command -v host >/dev/null 2>&1; then
    CURRENT_IP=$(host $HOSTNAME 2>/dev/null | grep 'has address' | awk '{print $4}')
fi

# 3. Méthode nslookup
if [ -z "$CURRENT_IP" ] && command -v nslookup >/dev/null 2>&1; then
    CURRENT_IP=$(nslookup $HOSTNAME 2>/dev/null | grep -A1 'Name:' | grep 'Address:' | tail -1 | awk '{print $2}')
fi

# 4. Méthode dig (peu probable sur Synology mais on garde au cas où)
if [ -z "$CURRENT_IP" ] && command -v dig >/dev/null 2>&1; then
    CURRENT_IP=$(dig +short $HOSTNAME)
fi

# 5. Méthode getent (disponible sur certains systèmes Linux)
if [ -z "$CURRENT_IP" ] && command -v getent >/dev/null 2>&1; then
    CURRENT_IP=$(getent hosts $HOSTNAME | awk '{print $1}')
fi

if [ -z "$CURRENT_IP" ]; then
    echo "Erreur: Impossible de résoudre le hostname $HOSTNAME avec aucune méthode"
    exit 1
fi

echo "Adresse IP actuelle pour $HOSTNAME: $CURRENT_IP"

# Créer le fichier d'historique s'il n'existe pas
if [ ! -f "$IP_HISTORY_FILE" ]; then
    echo "Création du fichier d'historique pour $HOSTNAME..."
    echo "# Historique des IPs pour $HOSTNAME" > "$IP_HISTORY_FILE"
    echo "# Format: DATE IP" >> "$IP_HISTORY_FILE"
    echo "LAST_IP=" >> "$IP_HISTORY_FILE"
fi

# Lire la dernière IP connue
LAST_IP=$(grep -E "^LAST_IP=" "$IP_HISTORY_FILE" | cut -d'=' -f2)

echo "Dernière IP connue pour $HOSTNAME: $LAST_IP"
echo "(Le fichier d'historique est stocké dans $IP_HISTORY_FILE)"

# Si l'IP a changé
if [ "$CURRENT_IP" != "$LAST_IP" ]; then
    echo "L'adresse IP a changé de $LAST_IP à $CURRENT_IP"
    
    # Si une IP précédente existe, la supprimer du firewall
    if [ -n "$LAST_IP" ]; then
        echo "Suppression de l'ancienne règle pour $HOSTNAME..."
        "$SCRIPT_DIR/remove_firewall_ip.sh" "$HOSTNAME"
    fi
    
    # Ajouter la nouvelle IP
    echo "Ajout de la nouvelle IP $CURRENT_IP pour $HOSTNAME..."
    "$SCRIPT_DIR/add_firewall_ip.sh" "$CURRENT_IP" "$HOSTNAME"
    
    # Mettre à jour l'historique
    sed -i "s/^LAST_IP=.*/LAST_IP=$CURRENT_IP/" "$IP_HISTORY_FILE"
    echo "$(date +'%Y-%m-%d %H:%M:%S') $CURRENT_IP" >> "$IP_HISTORY_FILE"
    
    echo "Mise à jour du firewall terminée avec succès"    
else
    echo "L'adresse IP n'a pas changé, aucune action nécessaire"
fi