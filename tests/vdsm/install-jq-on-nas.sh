#!/bin/bash

ENV_FILE=".env"

if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

if [ -z "$DSM_USER" ]; then
  read -p "👤 DSM Username: " DSM_USER
fi

DSM_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dsm)
REMOTE_BIN="/var/services/homes/${DSM_USER}/bin"

# Download jq locally if not present
if [ ! -f ./jq ]; then
  echo "⬇️ Downloading jq binary..."
  curl -Lo jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
  chmod +x jq
fi

# Send jq to the NAS
echo "📤 Sending jq to $DSM_USER@$DSM_IP:$REMOTE_BIN"
ssh "$DSM_USER@$DSM_IP" "mkdir -p $REMOTE_BIN"
cat jq | ssh "$DSM_USER@$DSM_IP" "cat > $REMOTE_BIN/jq && chmod +x $REMOTE_BIN/jq"

# Clean up local copy
echo "🧹 Cleaning up local jq copy..."
rm -f jq

# Add export line to profile if not already present
echo "📦 Ensuring jq is available on DSM shell..."
ssh "$DSM_USER@$DSM_IP" "grep -qxF 'export PATH=\"$REMOTE_BIN:\$PATH\"' ~/.profile || echo 'export PATH=\"$REMOTE_BIN:\$PATH\"' >> ~/.profile"

echo "✅ jq installed at $REMOTE_BIN/jq and added to PATH"
