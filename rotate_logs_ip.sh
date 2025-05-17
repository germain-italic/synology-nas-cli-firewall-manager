#!/bin/bash

# Rotation du fichier log principal
LOG_FILE="/var/log/update_noip.log"
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 1048576 ]; then
    echo "Rotation du fichier log principal: $LOG_FILE"
    mv "$LOG_FILE" "${LOG_FILE}.1"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
fi

# Rotation des fichiers d'historique par hostname
HISTORY_DIR="/volume1/homes/$(whoami)/firewall_history"
MAX_SIZE=1048576  # 1MB

# Vérifier si le répertoire d'historique existe
if [ -d "$HISTORY_DIR" ]; then
    echo "Vérification des fichiers d'historique dans $HISTORY_DIR..."
    
    # Parcourir tous les fichiers d'historique
    for history_file in "$HISTORY_DIR"/*.history; do
        if [ -f "$history_file" ]; then
            # Extraire les informations importantes du fichier
            hostname_line=$(grep "^# Historique des IPs pour" "$history_file" | head -1)
            last_ip=$(grep "^LAST_IP=" "$history_file" | cut -d'=' -f2)
            
            # Vérifier la taille du fichier
            file_size=$(stat -c%s "$history_file")
            if [ "$file_size" -gt "$MAX_SIZE" ]; then
                echo "Rotation du fichier d'historique: $history_file"
                
                # Créer un fichier de sauvegarde
                backup_file="${history_file}.$(date +%Y%m%d)"
                
                # Si le fichier de sauvegarde existe déjà, ajouter un numéro
                counter=1
                while [ -f "$backup_file" ]; do
                    backup_file="${history_file}.$(date +%Y%m%d).$counter"
                    counter=$((counter + 1))
                done
                
                # Faire la rotation
                cp "$history_file" "$backup_file"
                
                # Recréer un nouveau fichier avec seulement les informations essentielles
                echo "$hostname_line" > "$history_file"
                echo "# Format: DATE IP" >> "$history_file"
                echo "LAST_IP=$last_ip" >> "$history_file"
                
                # Ajouter les 10 dernières entrées d'IP pour référence
                tail -10 "$backup_file" | grep -v "^#" | grep -v "^LAST_IP=" >> "$history_file"
                
                echo "Rotation terminée: $history_file -> $backup_file"
            fi
        fi
    done
else
    echo "Répertoire d'historique non trouvé: $HISTORY_DIR"
fi