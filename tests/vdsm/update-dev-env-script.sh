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
