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
  log "Waiting for all pods in namespace '$NAMESPACE' to be ready..."

  while true; do
    NOT_READY=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print $2}' | grep -v "1/1" | wc -l)
    TOTAL=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)

    if [ "$NOT_READY" -eq 0 ] && [ "$TOTAL" -gt 0 ]; then
      log "All pods are ready!"
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

# Start Minikube only if it's not running
if ! minikube status | grep -q "host: Running"; then
  log "Starting Minikube..."
  minikube start --driver=docker
else
  log "Minikube is already running. Skipping start."
fi

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

# Install or upgrade RabbitMQ Operator only if it's not already installed
if ! helm list -n rabbitmq-system | grep -q rabbitmq-operator; then
  log "Installing RabbitMQ Operator..."
  helm upgrade --install rabbitmq-operator bitnami/rabbitmq-cluster-operator --namespace rabbitmq-system --create-namespace
else
  log "RabbitMQ Operator already installed. Skipping."
fi

# Install Cert Manager only if cert-manager namespace does not exist
if ! kubectl get ns cert-manager &>/dev/null; then
  log "Installing Cert Manager..."
  kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.3.1/cert-manager.yaml
else
  log "Cert Manager already installed. Skipping."
fi

# Wait for cert-manager-webhook to be ready (only if not ready)
if ! kubectl -n cert-manager get deployment cert-manager-webhook &>/dev/null || \
   ! kubectl -n cert-manager rollout status deployment cert-manager-webhook --timeout=5s; then
  log "Waiting for cert-manager webhook to be ready..."
  kubectl -n cert-manager rollout status deployment cert-manager-webhook --timeout=120s
else
  log "cert-manager-webhook is already ready. Skipping wait."
fi

# Install RabbitMQ Messaging Topology Operator only if CRDs are not present
log "Checking if Messaging Topology Operator is installed..."
if ! kubectl -n rabbitmq-system get deployment messaging-topology-operator &>/dev/null; then
  log "Installing RabbitMQ Messaging Topology Operator..."
  kubectl apply -f https://github.com/rabbitmq/messaging-topology-operator/releases/latest/download/messaging-topology-operator-with-certmanager.yaml
  log "Waiting for Messaging Topology Operator to become ready..."
kubectl -n rabbitmq-system rollout status deployment messaging-topology-operator --timeout=60s
else
  log "Messaging Topology Operator already installed. Skipping."
fi


success "Installation complete!"

log "Displaying pods in rabbitmq-system for convenience"
kubectl get pods -n rabbitmq-system
log "Displaying rabbitmq cluster for convenience"
kubectl get rabbitmqclusters -n rabbitmq-system
# Wait for RabbitMQ pods to be fully running
wait_for_pods_ready rabbitmq-system


log "Checking if RabbitMQ messaging topology already exists..."
error "The current method of checking if the topology is running does not work and and is pending a better solution"
USER_EXISTS=$(kubectl get users.rabbitmq.com -n rabbitmq-system -l app=rabbitmq-topology --no-headers | wc -l)
PERMISSION_EXISTS=$(kubectl get permissions.rabbitmq.com -n rabbitmq-system -l app=rabbitmq-topology --no-headers | wc -l)
QUEUE_EXISTS=$(kubectl get queues.rabbitmq.com -n rabbitmq-system -l app=rabbitmq-topology --no-headers | wc -l)

if [ "$USER_EXISTS" -gt 0 ] && [ "$PERMISSION_EXISTS" -gt 0 ] && [ "$QUEUE_EXISTS" -gt 0 ]; then
  log "All RabbitMQ messaging topology resources exist. Skipping setup."
else
  log "Applying RabbitMQ messaging topology"
  kubectl apply -f rabbitmq-topology.yaml

  log "Ensuring no previous RabbitMQ port-forward is running..."
  pkill -f "kubectl port-forward svc/rabbitmq-ha" || true

  log "Starting port-forward for RabbitMQ management UI..."
  kubectl port-forward svc/rabbitmq-ha -n rabbitmq-system 15672:15672 &

  sleep 5
fi

log "Fetching RabbitMQ UI credentials:"
echo "Username:"
kubectl get secret rabbitmq-ha-default-user -n rabbitmq-system -o jsonpath="{.data.username}" | base64 -d && echo
echo "Password:"
kubectl get secret rabbitmq-ha-default-user -n rabbitmq-system -o jsonpath="{.data.password}" | base64 -d && echo

log "Applying RabbitMQ messaging topology"
kubectl apply -f rabbitmq-topology.yaml

