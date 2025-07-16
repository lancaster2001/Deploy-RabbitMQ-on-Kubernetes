#!/bin/bash
set -e
# Colors for output
YELLOW="\e[33m"
GREEN="\e[32m"
RED="\e[31m"
NC="\e[0m"
log() {
    echo -e "${YELLOW}[LOG]${NC} $1"
}
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}
error() {
    echo -e "${RED}$1${NC}"
}

log "Installing prerequisite packages"
sudo apt-get install -y apt-transport-https software-properties-common wget

sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list

log "\"apt-get update\""
sudo apt-get update

log "Installing Grafana..."
sudo apt-get install grafana

log "Reloading daemon.."
sudo systemctl daemon-reload
log "Starting grafana server..."
sudo systemctl start grafana-server
sudo systemctl status grafana-server

log "Enabling start on boot"
sudo systemctl status grafana-server

log "Creating systemd override to allow Grafana to bind to privileged ports (<1024)..."

# Path to the override directory and file
OVERRIDE_DIR="/etc/systemd/system/grafana-server.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"

# Create directory if it doesn't exist
sudo mkdir -p "$OVERRIDE_DIR"

# Write override configuration
sudo tee "$OVERRIDE_FILE" > /dev/null <<EOF
[Service]
# Give the CAP_NET_BIND_SERVICE capability
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateUsers=false
EOF

#log Reloading systemd daemon...
#sudo systemctl daemon-reexec
#sudo systemctl daemon-reload

log "Restarting grafana-server service..."
sudo systemctl restart grafana-server
success "Grafana is now allowed to bind to ports less than 1024"
