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
    0)
      echo "👋 Exiting."
      exit 0
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
