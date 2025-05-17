#!/bin/bash

set -e

CONTAINER_NAME="dsm"
DSM_URL="http://localhost:5000"

print_menu() {
  echo ""
  echo "=========================="
  echo " Virtual DSM Control Menu"
  echo "=========================="
  echo "1) Start DSM"
  echo "2) Restart DSM"
  echo "3) Stop DSM"
  echo "4) Show logs"
  echo "5) Show container IP"
  echo "6) Show container health status"
  echo "7) Open DSM in browser"
  echo "8) Enable SSH on DSM (via API)"
  echo "9) Enable home directories on DSM (via API)"
  echo "10) Send SSH public key to DSM (via ssh-copy-id)"
  echo "11) Connect to DSM via SSH"
  echo "0) Exit"
  echo ""
  read -p "Choose an option: " CHOICE
}

handle_choice() {
  case $CHOICE in
    1)
      echo "▶️ Starting DSM..."
      docker-compose up -d
      ;;
    2)
      echo "🔁 Restarting DSM..."
      docker-compose down
      docker-compose up -d
      ;;
    3)
      echo "⏹️ Stopping DSM..."
      docker-compose down
      ;;
    4)
      echo "📜 Logs (Ctrl+C to quit):"
      docker logs -f "$CONTAINER_NAME"
      ;;
    5)
      echo "🌐 DSM Container IP:"
      docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME"
      ;;
    6)
      echo "❤️ DSM Container Health Status:"
      STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "not running")
      HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "n/a")
      echo "Status:  $STATUS"
      echo "Health:  $HEALTH"
      ;;
    7)
      echo "🌍 Opening DSM at $DSM_URL ..."
      if command -v xdg-open &>/dev/null; then
        xdg-open "$DSM_URL"
      elif command -v wslview &>/dev/null; then
        wslview "$DSM_URL"
      else
        echo "🔗 Please open this URL in your browser:"
        echo "$DSM_URL"
      fi
      ;;
    8)
      if [ -x ./enable-ssh.sh ]; then
        echo "🛰 Running enable-ssh.sh..."
        ./enable-ssh.sh
      else
        echo "⚠️ Script enable-ssh.sh not found or not executable."
      fi
      ;;
    9)
      if [ -x ./enable-homes.sh ]; then
        echo "🛰 Running enable-homes.sh..."
        ./enable-homes.sh
      else
        echo "⚠️ Script enable-homes.sh not found or not executable."
      fi
      ;;
    0)
      echo "👋 Exiting."
      exit 0
      ;;

    10)
      ENV_FILE=".env"
      if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
      fi

      if [[ -z "$DSM_USER" ]]; then
        read -p "👤 DSM Username: " DSM_USER
      fi

      if [[ -z "$SSH_KEY_PATH" ]]; then
        SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"
      fi

      if [[ ! -f "$SSH_KEY_PATH" ]]; then
        echo "❌ SSH public key not found at $SSH_KEY_PATH"
      else
        DSM_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")
        echo "📤 Sending SSH key ($SSH_KEY_PATH) to $DSM_USER@$DSM_IP ..."
        ssh-copy-id -i "$SSH_KEY_PATH" "$DSM_USER@$DSM_IP"
      fi
      ;;

    11)
      ENV_FILE=".env"
      if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
      fi

      if [[ -z "$DSM_USER" ]]; then
        read -p "👤 DSM Username: " DSM_USER
      fi

      DSM_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")

      if [[ -z "$DSM_IP" ]]; then
        echo "❌ Could not determine DSM container IP."
      else
        echo "📡 Connecting via SSH to $DSM_USER@$DSM_IP ..."
        ssh "$DSM_USER@$DSM_IP"
      fi
      ;;

    *)
      echo "❌ Invalid choice."
      ;;
  esac
}

while true; do
  print_menu
  handle_choice
done
