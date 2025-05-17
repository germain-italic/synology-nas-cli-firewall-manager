#!/bin/bash

ENV_FILE=".env"

if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

DSM_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dsm)

if [ -z "$DSM_USER" ]; then
  read -p "👤 DSM Username: " DSM_USER
fi

# Determine SSH key path correctly
if [ -z "$SSH_KEY_PATH" ]; then
  SSH_KEY_PATH="$HOME/.ssh/id_rsa"
  SSH_PUBLIC_KEY="${SSH_KEY_PATH}.pub"
  echo "ℹ️ Using default SSH key: $SSH_KEY_PATH"
else
  # If SSH_KEY_PATH points to the public key, get the private key path
  if [[ "$SSH_KEY_PATH" == *.pub ]]; then
    SSH_PUBLIC_KEY="$SSH_KEY_PATH"
    SSH_KEY_PATH="${SSH_PUBLIC_KEY%.pub}"
    echo "ℹ️ Using SSH key from .env (adjusted): $SSH_KEY_PATH"
  else
    SSH_PUBLIC_KEY="${SSH_KEY_PATH}.pub"
    echo "ℹ️ Using SSH key from .env: $SSH_KEY_PATH"
  fi
fi

echo "🔑 Private key: $SSH_KEY_PATH"
echo "🔑 Public key: $SSH_PUBLIC_KEY"

if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "❌ SSH private key not found at $SSH_KEY_PATH"
  exit 1
fi

if [ ! -f "$SSH_PUBLIC_KEY" ]; then
  echo "❌ SSH public key not found at $SSH_PUBLIC_KEY"
  exit 1
fi

# Send private and public keys to DSM
REMOTE_SSH_DIR="/var/services/homes/${DSM_USER}/.ssh"
echo "📤 Setting up SSH directory on DSM..."
ssh "$DSM_USER@$DSM_IP" "mkdir -p $REMOTE_SSH_DIR && chmod 700 $REMOTE_SSH_DIR"

# Create a more compatible format for the SSH key
echo "🔄 Preparing SSH keys in compatible format..."
TEMP_SSH_KEY=$(mktemp)
TEMP_SSH_PUB_KEY=$(mktemp)

# Convert the key to ensure compatibility with DSM
cat "$SSH_KEY_PATH" > "$TEMP_SSH_KEY"
cat "$SSH_PUBLIC_KEY" > "$TEMP_SSH_PUB_KEY"

echo "📤 Sending SSH private key to DSM..."
cat "$TEMP_SSH_KEY" | ssh "$DSM_USER@$DSM_IP" "cat > $REMOTE_SSH_DIR/id_rsa && chmod 600 $REMOTE_SSH_DIR/id_rsa"

echo "📤 Sending SSH public key to DSM..."
cat "$TEMP_SSH_PUB_KEY" | ssh "$DSM_USER@$DSM_IP" "cat > $REMOTE_SSH_DIR/id_rsa.pub && chmod 644 $REMOTE_SSH_DIR/id_rsa.pub"

# Clean up temp files
rm "$TEMP_SSH_KEY" "$TEMP_SSH_PUB_KEY"

# Configure SSH on DSM to accept the GitHub host key
echo "🔑 Configuring SSH on DSM to accept GitHub's host key..."
# Using a temporary known_hosts file approach instead of ssh-keyscan
TEMP_KNOWN_HOSTS=$(mktemp)
cat << EOF > "$TEMP_KNOWN_HOSTS"
github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
EOF

# Send the temporary known_hosts file to the DSM
echo "📤 Sending GitHub host keys to DSM..."
cat "$TEMP_KNOWN_HOSTS" | ssh "$DSM_USER@$DSM_IP" "cat >> $REMOTE_SSH_DIR/known_hosts"
rm "$TEMP_KNOWN_HOSTS"

# Try using HTTPS instead of SSH for Git
REMOTE_SCRIPT="setup-dev-env-on-nas.sh"
REMOTE_PATH="/var/services/homes/${DSM_USER}/${REMOTE_SCRIPT}"

echo "📝 Generating modified setup script using HTTPS for Git..."
cat > /tmp/temp_setup.sh << 'EOF'
#!/bin/bash

set -e

# Test Git connection
echo "🔍 Testing Git command..."
if ! command -v git &> /dev/null; then
  echo "❌ Git not installed. Installing..."
  /usr/syno/bin/synopkg install git
fi

# Using HTTPS URL instead of SSH
REPO_URL="https://github.com/germain-italic/synology-nas-cli-firewall-manager.git"
TARGET_DIR="/var/services/homes/$USER/synology-nas-cli-firewall-manager"

echo "👤 Running as user: $USER"
echo "🏠 Home directory: /var/services/homes/$USER"

# Ensure target directory
echo "📁 Creating directory: $(dirname "$TARGET_DIR")"
mkdir -p "$(dirname "$TARGET_DIR")"

# Clone repo if it doesn't exist
if [ ! -d "$TARGET_DIR/.git" ]; then
  echo "🔄 Cloning repository into $TARGET_DIR using HTTPS..."
  git clone "$REPO_URL" "$TARGET_DIR"
  echo "✅ Repository cloned successfully!"
else
  echo "📂 Repository already exists at $TARGET_DIR"
  echo "🔄 Updating repository..."
  cd "$TARGET_DIR" && git pull
  echo "✅ Repository updated successfully!"
fi

echo "🎉 Setup complete! Repository is available at:"
echo "$TARGET_DIR"
EOF

echo "📤 Sending modified setup script to $DSM_USER@$DSM_IP using SSH..."
cat /tmp/temp_setup.sh | ssh "$DSM_USER@$DSM_IP" "cat > $REMOTE_PATH"
rm /tmp/temp_setup.sh

echo "🚀 Running setup script on DSM..."
ssh "$DSM_USER@$DSM_IP" "chmod +x $REMOTE_PATH && $REMOTE_PATH"
