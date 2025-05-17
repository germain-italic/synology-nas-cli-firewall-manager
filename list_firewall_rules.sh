#!/bin/bash

FIREWALL_DIR="/usr/syno/etc/firewall.d"
SETTINGS_FILE="$FIREWALL_DIR/firewall_settings.json"

# Déterminer le profil actif
PROFILE_NAME=$(grep -o '"profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed -E 's/"profile"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/')
echo "Profil actif: $PROFILE_NAME"

# Trouver le fichier de profil contenant le nom du profil actif
PROFILE_FILE=""
for f in "$FIREWALL_DIR"/*.json; do
    # Ignorer le fichier de settings
    if [ "$f" = "$SETTINGS_FILE" ] || [[ "$f" == *".backup."* ]]; then
        continue
    fi
    
    # Vérifier si ce fichier contient le nom du profil actif
    if grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$PROFILE_NAME\"" "$f"; then
        PROFILE_FILE="$f"
        break
    fi
done

if [ -z "$PROFILE_FILE" ]; then
    echo "Aucun fichier de profil trouvé pour le profil '$PROFILE_NAME'"
    exit 1
fi

echo "Fichier de profil: $PROFILE_FILE"
echo "---------------------------------------------------------------------------------------------"
printf "| %-34s | %-38s | %-7s |\n" "Rule Name" "IP Address(es)" "Enabled"
echo "---------------------------------------------------------------------------------------------"

if command -v jq >/dev/null 2>&1; then
    jq -r '
      .rules.global[]
      | select(.ipList | type == "array" and length > 0)
      | [(if (.name | tostring | length) > 0 then .name else "-" end), (.ipList | join(", ")), (.enable // false)]
      | @tsv
    ' "$PROFILE_FILE" | while IFS=$'\t' read -r name iplist enabled; do
        printf "| %-34s | %-38s | %-7s |\n" "$name" "$iplist" "$enabled"
    done
else
    echo "jq n'est pas disponible, impossible d'afficher les règles"
    
    # Alternative simple si jq n'est pas disponible
    echo "Contenu brut des règles IP:"
    grep -A 20 '"ipList"' "$PROFILE_FILE" | grep -B 20 '"table"' | sed 's/^/  /'
fi

echo "---------------------------------------------------------------------------------------------"