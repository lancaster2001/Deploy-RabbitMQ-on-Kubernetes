#!/bin/bash
set -e
# Colors for output
YELLOW="\e[33m"
GREEN="\e[32m"
RED="\e[31m"
NC="\e[0m"
log() {source ${script-path}/initial-setup.sh
    echo -e "${YELLOW}[LOG]${NC} $1"
}
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}
error() {
    echo -e "${RED}$1${NC}"
}

#get path to this script
script-path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "Setting up build"
source ${script-path}/initial-setup.sh

log "Building the monitor ddashboard"
source ${script-path}/monitoring-build.sh
