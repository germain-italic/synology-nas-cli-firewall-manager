#!/bin/bash

set -e

# Test SSH connection to GitHub
echo "🔑 Testing SSH connection to GitHub..."
if ! ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | grep -q "success"; then
  echo "⚠️ Warning: SSH connection to GitHub may have issues."
  echo "🔍 Trying alternative approach..."
  # Continue anyway, it might still work
fi

REPO_URL="git@github.com:germain-italic/synology-nas-cli-firewall-manager.git"
# Change target directory to user's home directory
TARGET_DIR="/var/services/homes/$USER/dev/synology-nas-cli-firewall-manager"

echo "👤 Running as user: $USER"
echo "🏠 Home directory: /var/services/homes/$USER"

# Install git if not available
if ! command -v git &> /dev/null; then
  echo "📦 Installing git..."
  /usr/syno/bin/synopkg install git
fi

# Ensure target directory
echo "📁 Creating directory: $(dirname "$TARGET_DIR")"
mkdir -p "$(dirname "$TARGET_DIR")"

# Clone repo if it doesn't exist
if [ ! -d "$TARGET_DIR/.git" ]; then
  echo "🔄 Cloning repository into $TARGET_DIR..."
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
