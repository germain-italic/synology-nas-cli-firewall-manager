#!/bin/bash

# Ce script supprime une règle du firewall Synology DSM 7.x en se basant sur le nom de la règle
# Usage: ./remove_firewall_ip.sh <rule_name>
# Le rule_name peut être un hostname ou une adresse IP (selon ce qui a été utilisé lors de l'ajout)

# Vérifier si un nom de règle a été fourni
if [ $# -ne 1 ]; then
    echo "Usage: $0 <rule_name>"
    echo "Exemple: $0 maison.ddns.net  OU  $0 192.168.1.100"
    exit 1
fi

# Nom de la règle à supprimer (peut être un hostname ou une adresse IP)
RULE_NAME="$1"

# Chemin vers les fichiers de configuration du firewall
FIREWALL_DIR="/usr/syno/etc/firewall.d"

# Obtenir le profil actif
SETTINGS_FILE="$FIREWALL_DIR/firewall_settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Erreur: Fichier de paramètres du firewall introuvable"
    exit 1
fi

# Déterminer le profil actif
PROFILE_NAME=$(grep -o '"profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed -E 's/"profile"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/')
echo "Profil actif: $PROFILE_NAME"

# Trouver le fichier de profil contenant le nom du profil actif
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

if [ -z "$PROFILE_FILE" ] || [ ! -f "$PROFILE_FILE" ]; then
    echo "Erreur: Fichier de profil introuvable"
    exit 1
fi

echo "Fichier de profil à modifier: $PROFILE_FILE"

# Faire une sauvegarde du fichier
BACKUP_FILE="${PROFILE_FILE}.backup.$(date +%Y%m%d%H%M%S)"
cp "$PROFILE_FILE" "$BACKUP_FILE"
echo "Sauvegarde créée: $BACKUP_FILE"

# Vérifier si le nom de règle existe dans le fichier
if ! grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$RULE_NAME\"" "$PROFILE_FILE"; then
    echo "Aucune règle avec le nom $RULE_NAME n'a été trouvée"
    
    # Vérifier si le RULE_NAME est une adresse IP qui pourrait être présente dans les règles iptables
    if [[ $RULE_NAME =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        if iptables -S | grep -q "$RULE_NAME"; then
            echo "L'adresse IP $RULE_NAME est présente dans les règles iptables, mais pas dans le fichier de configuration"
            echo "Suppression des règles iptables uniquement..."
            iptables -t filter -D FORWARD_FIREWALL -s "$RULE_NAME" -j RETURN 2>/dev/null
            iptables -t filter -D INPUT_FIREWALL -s "$RULE_NAME" -j RETURN 2>/dev/null
            echo "Règles iptables supprimées."
            exit 0
        fi
    fi
    
    echo "Aucune action nécessaire."
    exit 0
fi

# Extraire l'adresse IP associée au nom de règle pour la supprimer des règles iptables
IP_ADDRESS=""
if command -v jq >/dev/null 2>&1; then
    IP_ADDRESS=$(jq -r --arg name "$RULE_NAME" '.rules.global[] | select(.name == $name) | .ipList[0]' "$PROFILE_FILE")
    
    if [ -n "$IP_ADDRESS" ]; then
        echo "Adresse IP associée au nom de règle $RULE_NAME: $IP_ADDRESS"
    else
        echo "Impossible de déterminer l'adresse IP associée au nom de règle $RULE_NAME"
    fi
    
    # Supprimer la règle contenant le nom spécifié
    TMP_FILE=$(mktemp)
    
    jq --arg name "$RULE_NAME" '
    .rules.global = (.rules.global | map(
        select(.name != $name)
    ))
    ' "$PROFILE_FILE" > "$TMP_FILE"
    
    # Vérifier que le fichier temporaire est valide et non vide
    if [ -s "$TMP_FILE" ] && jq empty "$TMP_FILE" 2>/dev/null; then
        echo "Modification réussie, application des changements"
        cp "$TMP_FILE" "$PROFILE_FILE"
        rm -f "$TMP_FILE"
    else
        echo "Erreur lors de la modification du fichier JSON"
        rm -f "$TMP_FILE"
        exit 1
    fi
else
    echo "jq n'est pas disponible, impossible de supprimer la règle correctement"
    exit 1
fi

# Si une adresse IP a été trouvée, la supprimer des règles iptables
if [ -n "$IP_ADDRESS" ]; then
    echo "Suppression des règles iptables pour $IP_ADDRESS"
    iptables -t filter -D FORWARD_FIREWALL -s "$IP_ADDRESS" -j RETURN 2>/dev/null
    iptables -t filter -D INPUT_FIREWALL -s "$IP_ADDRESS" -j RETURN 2>/dev/null
fi

# Recharger le firewall
echo "Rechargement du firewall..."
if ! /usr/syno/bin/synofirewall --reload; then
    echo "Erreur lors du rechargement du firewall!"
    echo "Restauration de la sauvegarde..."
    cp "$BACKUP_FILE" "$PROFILE_FILE"
    /usr/syno/bin/synofirewall --reload
    echo "Sauvegarde restaurée"
    exit 1
fi

echo "Règle pour $RULE_NAME supprimée avec succès"

# Vérifier que le nom de règle a bien été supprimé
if grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$RULE_NAME\"" "$PROFILE_FILE"; then
    echo "ATTENTION: Le nom de règle est toujours présent dans le fichier de configuration"
else
    echo "Vérification réussie: le nom de règle a bien été supprimé du fichier de configuration"
fi

# Vérifier que l'IP a bien été supprimée des règles iptables, si elle était connue
if [ -n "$IP_ADDRESS" ] && iptables -S | grep -q "$IP_ADDRESS"; then
    echo "ATTENTION: L'IP est toujours présente dans les règles iptables"
else
    echo "Vérification réussie: les règles iptables ont été correctement mises à jour"
fi