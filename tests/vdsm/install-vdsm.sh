#!/bin/bash
set -e

echo "🔍 Checking for Docker..."

if ! command -v docker &> /dev/null; then
  echo "🚀 Docker not found. Installing..."
  sudo apt update
  sudo apt install -y docker.io
  sudo usermod -aG docker $USER
  newgrp docker
else
  echo "✅ Docker is already installed."
fi

echo "🔍 Checking for Docker Compose..."

if docker compose version &> /dev/null; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  COMPOSE_CMD="docker-compose"
else
  echo "❌ Neither 'docker compose' nor 'docker-compose' is available."
  exit 1
fi


echo "✅ Checking for /dev/kvm..."
if [ ! -e /dev/kvm ]; then
  echo "❌ /dev/kvm not found. Virtual DSM cannot run without it."
  exit 1
fi

echo "📁 Creating data directory (./data)..."
mkdir -p ./data

if [ -f docker-compose.yml ]; then
  echo "📝 docker-compose.yml already exists. Skipping creation."
else
  echo "📝 Creating docker-compose.yml..."
  cat > docker-compose.yml <<EOF
version: '3.9'
services:
  dsm:
    container_name: dsm
    image: vdsm/virtual-dsm
    environment:
      DISK_SIZE: "16G"
      DISK_FMT: "qcow2"
      RAM_SIZE: "4G"
      CPU_CORES: "4"
      GPU: "Y"
    devices:
      - /dev/kvm
      - /dev/net/tun
      - /dev/vhost-net
      - /dev/dri
    volumes:
      - ./data:/storage
    cap_add:
      - NET_ADMIN
    privileged: true
    stop_grace_period: 2m
    ports:
      - "5000:5000"  # DSM Web UI
      - "22:22"      # SSH
      - "445:445"    # SMB
      - "139:139"    # SMB
EOF
fi

echo "🚀 Checking if the DSM container is already running..."
if docker ps --filter "name=^/${CONTAINER_NAME}$" --filter "status=running" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "✅ DSM container '${CONTAINER_NAME}' is already running. Skipping startup."
else
  echo "🚀 Starting Virtual DSM using ${COMPOSE_CMD}..."
  $COMPOSE_CMD up -d
fi

echo "🔚 Installation complete."
echo "✅ Virtual DSM is now running. Open http://localhost:5000 in your browser."
echo "📜 To view logs, run: docker logs -f dsm"
echo "🛑 To stop the Virtual DSM, run: ${COMPOSE_CMD} down"
echo ""
echo "🧭 To manage DSM via interactive menu, run:"
echo "    ./vdsm-control.sh"
echo ""

# Automatically launch the control menu if the script exists and is executable
if [ -x ./vdsm-control.sh ]; then
  echo "▶️ Launching DSM control menu..."
  ./vdsm-control.sh
else
  echo "⚠️ vdsm-control.sh not found or not executable."
fi