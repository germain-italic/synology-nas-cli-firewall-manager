#!/bin/bash

# Ce script ajoute une IP à la whitelist du firewall Synology DSM 7.x
# Usage: ./add_firewall_ip.sh <adresse_ip> [hostname]
# Si hostname n'est pas fourni, l'adresse IP sera utilisée comme nom

# Vérifier si au moins une adresse IP a été fournie
if [ $# -lt 1 ]; then
    echo "Usage: $0 <adresse_ip> [hostname]"
    echo "Exemple: $0 192.168.1.100 maison.ddns.net"
    exit 1
fi

# Adresse IP à ajouter
IP_TO_ADD="$1"

# Utiliser le hostname fourni ou par défaut l'adresse IP comme nom
if [ $# -gt 1 ]; then
    RULE_NAME="$2"
else
    RULE_NAME="$IP_TO_ADD"
    echo "Aucun hostname fourni, utilisation de l'adresse IP comme nom de la règle"
fi

# Vérifier le format de l'IP (validation basique)
if ! [[ $IP_TO_ADD =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Erreur: Format d'adresse IP invalide"
    exit 1
fi

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

# Vérifier si le nom de règle existe déjà dans le fichier
if grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$RULE_NAME\"" "$PROFILE_FILE"; then
    echo "Une règle avec le nom $RULE_NAME existe déjà"
    echo "Utilisez remove_firewall_ip.sh pour supprimer la règle existante d'abord"
    exit 0
fi

# Vérifier si l'IP existe déjà dans les règles iptables
if iptables -S | grep -q "$IP_TO_ADD"; then
    echo "INFO: L'adresse IP $IP_TO_ADD est déjà présente dans les règles iptables"
fi

# Vérifier la structure du JSON et identifier l'index de la règle deny
if command -v jq >/dev/null 2>&1; then
    # Vérifier si le fichier est un JSON valide
    if ! jq empty "$PROFILE_FILE" 2>/dev/null; then
        echo "Erreur: Le fichier de profil n'est pas un JSON valide"
        exit 1
    fi
    
    # Trouver l'index de la règle deny (policy=1)
    DENY_INDEX=$(jq '.rules.global | map(.policy) | index(1)' "$PROFILE_FILE")
    
    if [ "$DENY_INDEX" = "null" ] || [ -z "$DENY_INDEX" ]; then
        echo "Aucune règle deny trouvée. La nouvelle règle sera ajoutée à la fin."
        DENY_INDEX=$(jq '.rules.global | length' "$PROFILE_FILE")
    fi
    
    echo "Position de la règle deny: $DENY_INDEX"
    
    # Créer un fichier temporaire
    TMP_FILE=$(mktemp)
    
    # Créer la nouvelle règle et l'insérer avant la règle deny
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
    echo "jq n'est pas disponible, impossible d'ajouter la règle correctement"
    exit 1
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

echo "Adresse IP $IP_TO_ADD ajoutée à la whitelist avec le nom $RULE_NAME"

# Vérifier que l'IP est bien dans les règles iptables
if iptables -S | grep -q "$IP_TO_ADD"; then
    echo "Vérification réussie: l'IP est correctement présente dans les règles iptables"
else
    echo "ATTENTION: L'IP n'est pas présente dans les règles iptables"
fi

# Vérifier que le nom de règle est bien dans le fichier de configuration
if grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$RULE_NAME\"" "$PROFILE_FILE"; then
    echo "Vérification réussie: le nom de règle a bien été ajouté au fichier de configuration"
else
    echo "ATTENTION: Le nom de règle ne semble pas être dans le fichier de configuration"
fi