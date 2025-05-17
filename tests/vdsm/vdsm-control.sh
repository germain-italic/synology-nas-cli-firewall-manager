#!/bin/bash

set -e

# Load environment variables from .env file
ENV_FILE=".env"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
fi

# Set defaults if not defined in .env
CONTAINER_NAME="${CONTAINER_NAME:-dsm}"
DSM_URL="${DSM_URL:-http://localhost:5000}"
DSM_PORT="${DSM_PORT:-5000}"

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
  echo "11) Connect to DSM (via SSH)"
  echo "12) Install jq on DSM (via SSH)"
  echo "13) Display instructions to activate Git in DSM"
  echo "14) Deploy and setup development environment on NAS"
  echo "15) Update development environment on NAS (git pull)"
  echo "0) Exit"
  echo ""
  read -p "Choose an option: " CHOICE
}

handle_choice() {
  case $CHOICE in
    0)
      echo "👋 Exiting."
      exit 0
      ;;
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
    10)
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

    12)
      if [ -x ./install-jq-on-nas.sh ]; then
        echo "🛰 Running install-jq-on-nas.sh..."
        ./install-jq-on-nas.sh
      else
        echo "⚠️ Script install-jq-on-nas.sh not found or not executable."
      fi
      ;;
      
    13)
      echo "🌐 Git Activation Instructions for DSM"
      echo "====================================="
      echo "1. Open DSM in your web browser at $DSM_URL"
      echo "2. Log in to DSM using your credentials"
      echo "3. Go to Package Center"
      echo "4. Search for 'Git'"
      echo "5. Click the 'Install' button for the Git package"
      echo "6. Once installed, you can access Git Server settings at:"
      echo "   $DSM_URL/webman/3rdparty/Git/index.cgi"
      echo ""
      echo "ℹ️ Note: After installation, Git settings can be accessed through the DSM interface"
      echo "   via Package Center > Installed > Git > Settings"
      ;;
      
    14)
      if [ -x ./deploy-and-setup-nas.sh ]; then
        echo "🚀 Running deploy-and-setup-nas.sh..."
        ./deploy-and-setup-nas.sh
      else
        echo "⚠️ Script deploy-and-setup-nas.sh not found or not executable."
        echo "Please make sure the script exists and has executable permissions."
        echo "You can set permissions with: chmod +x deploy-and-setup-nas.sh"
      fi
      ;;
      
    15)
      if [ -x ./update-dev-env-on-nas.sh ]; then
        echo "🔄 Running update-dev-env-on-nas.sh..."
        ./update-dev-env-on-nas.sh
      else
        echo "⚠️ Script update-dev-env-on-nas.sh not found or not executable."
        echo "Creating update script..."
        
        cat > ./update-dev-env-on-nas.sh << 'EOF'
#!/bin/bash

ENV_FILE=".env"

if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

DSM_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dsm)

if [ -z "$DSM_USER" ]; then
  read -p "👤 DSM Username: " DSM_USER
fi

# Define repo path using the successful path you reported
REPO_PATH="/var/services/homes/${DSM_USER}/synology-nas-cli-firewall-manager"

echo "🔄 Updating repository on DSM at path: $REPO_PATH"
ssh "$DSM_USER@$DSM_IP" "cd $REPO_PATH && git pull"

if [ $? -eq 0 ]; then
  echo "✅ Repository updated successfully!"
else
  echo "⚠️ There was an issue updating the repository."
  echo "🔍 Checking if repository exists..."
  
  if ssh "$DSM_USER@$DSM_IP" "[ -d $REPO_PATH/.git ]"; then
    echo "📂 Repository exists but update failed. You may need to resolve conflicts manually."
  else
    echo "❌ Repository not found at $REPO_PATH"
    echo "💡 You may need to deploy the environment first using option #14."
  fi
fi
EOF
        chmod +x ./update-dev-env-on-nas.sh
        echo "✅ Update script created. Running it now..."
        ./update-dev-env-on-nas.sh
      fi
      ;;

    *)
      echo "❌ Invalid choice."
      ;;
  esac
}

# Main loop
while true; do
  print_menu
  handle_choice
done
