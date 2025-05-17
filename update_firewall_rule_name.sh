#!/bin/bash

# Ce script met à jour le champ "name" d'une règle contenant une IP donnée
# Usage: ./update_firewall_rule_name.sh <IP> <nouveau_nom>

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <ip_address> <new_name>"
    exit 1
fi

TARGET_IP="$1"
NEW_NAME="$2"

FIREWALL_DIR="/usr/syno/etc/firewall.d"
SETTINGS_FILE="$FIREWALL_DIR/firewall_settings.json"

PROFILE_NAME=$(grep -o '"profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed -E 's/.*"([^"]*)"/\1/')
echo "Profil actif : $PROFILE_NAME"

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

if [ ! -f "$PROFILE_FILE" ]; then
    echo "Erreur : Fichier de profil introuvable"
    exit 1
fi

echo "Fichier de profil : $PROFILE_FILE"

# Sauvegarde
BACKUP_FILE="${PROFILE_FILE}.backup.$(date +%Y%m%d%H%M%S)"
cp "$PROFILE_FILE" "$BACKUP_FILE"
echo "Sauvegarde : $BACKUP_FILE"

# Mise à jour avec jq
TMP_FILE=$(mktemp)

jq --arg ip "$TARGET_IP" --arg name "$NEW_NAME" '
.rules.global |= map(
  if (.ipList | index($ip)) != null then
    .name = $name
  else
    .
  end
)' "$PROFILE_FILE" > "$TMP_FILE"

# Valider le résultat
if [ -s "$TMP_FILE" ] && jq empty "$TMP_FILE" 2>/dev/null; then
    cp "$TMP_FILE" "$PROFILE_FILE"
    echo "Nom mis à jour pour la règle contenant l'IP $TARGET_IP"
else
    echo "Erreur JSON : restauration de la sauvegarde"
    cp "$BACKUP_FILE" "$PROFILE_FILE"
    exit 1
fi

# Recharger le firewall
/usr/syno/bin/synofirewall --reload

rm -f "$TMP_FILE"

# Réafficher les règles
SCRIPT_DIR="$(dirname "$0")"
if [ -x "$SCRIPT_DIR/list_firewall_rules.sh" ]; then
    echo
    echo "Règles mises à jour :"
    "$SCRIPT_DIR/list_firewall_rules.sh"
fi