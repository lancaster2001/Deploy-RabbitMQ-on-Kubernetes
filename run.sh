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

#get path to this script
script_path=$(dirname "$0")

log "Setting up build"
./${script_path}/initial-setup.sh

log "Building the monitor ddashboard"
source ${script_path}/monitoring-build.sh
