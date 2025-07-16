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

log "Installing cert manager"
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.3.1/cert-manager.yaml
log "Installing operator"
kubectl apply -f https://github.com/rabbitmq/messaging-topology-operator/releases/latest/download/messaging-topology-operator-with-certmanager.yaml
