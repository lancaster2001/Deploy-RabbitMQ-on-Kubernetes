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

wait_for_pods_ready() {
  NAMESPACE=$1
  echo "[LOG] Waiting for all pods in namespace '$NAMESPACE' to be ready..."

  while true; do
    NOT_READY=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print $2}' | grep -v "1/1" | wc -l)
    TOTAL=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)

    if [ "$NOT_READY" -eq 0 ] && [ "$TOTAL" -gt 0 ]; then
      echo "[LOG] All pods are ready!"
      break
    fi

    sleep 5
  done
}

# start of script --------------------------------------------------------------------------------------------------------------
log "Updating system..."
sudo apt update && sudo apt upgrade -y

log "Installing required dependencies..."
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release conntrack

log "Installing Docker..."
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

log "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

log "Installing Minikube..."
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

log "Starting Minikube..."
minikube start --driver=docker

log "Waiting for Kubernetes to be ready..."
until kubectl get nodes &> /dev/null; do
    log "   ...waiting for kubectl"
    sleep 3
done

log "Installing RabbitMQ Operator using Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
log "Checking if namespace needs to be created..."
if kubectl get namespace rabbitmq-system >/dev/null 2>&1; then
  log "Namespace rabbitmq-system already exists."
else
  kubectl create namespace rabbitmq-system && log "namespace rabbitmq-system created."
fi

#sudo usermod -aG docker $USER && newgrp docker

log "Checking for 'docker' group..."
if getent group docker > /dev/null 2>&1; then
  log "'docker' group already exists."
else
  log "'docker' group does not exist. Creating it..."
  sudo groupadd docker
fi

if groups $USER | grep -qw docker; then
  log "User is already in the docker group."
else
  log "Adding user to docker group..."
  sudo usermod -aG docker $USER
fi

helm upgrade --install rabbitmq-operator bitnami/rabbitmq-cluster-operator --namespace rabbitmq-system

log "Installing Cert Manager"
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.3.1/cert-manager.yaml

log "Waiting for cert-manager webhook to be ready..."
kubectl -n cert-manager rollout status deployment cert-manager-webhook --timeout=120s

log "Installing RabbitMQ Messaging Topology Operator"
kubectl apply -f https://github.com/rabbitmq/messaging-topology-operator/releases/latest/download/messaging-topology-operator-with-certmanager.yaml

success "Installation complete!"

kubectl get pods -n rabbitmq-system

log "Applying RabbitMQ cluster configuration..."
kubectl apply -f rabbitmq-cluster.yaml

kubectl get rabbitmqclusters -n rabbitmq-system
log "Waiting for pods to be ready..."

# Wait for RabbitMQ pods to be fully running
wait_for_pods_ready rabbitmq-system

log "forwarding ports for rabbitmq-system"
kubectl port-forward svc/rabbitmq-ha -n rabbitmq-system 15672:15672

sleep 5

log "Fetching RabbitMQ UI credentials:"
echo "Username:"
kubectl get secret rabbitmq-ha-default-user -n rabbitmq-system -o jsonpath="{.data.username}" | base64 -d && echo
echo "Password:"
kubectl get secret rabbitmq-ha-default-user -n rabbitmq-system -o jsonpath="{.data.password}" | base64 -d && echo

log "Applying RabbitMQ messaging topology"
kubectl apply -f rabbitmq-topology.yaml

