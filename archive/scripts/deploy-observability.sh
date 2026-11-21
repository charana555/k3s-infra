#!/bin/bash
set -e

# Deploys the full observability stack: Prometheus + Grafana + Alertmanager + Loki + Alloy
# Helm values are tracked in helm/ directory
# Usage: ./scripts/deploy-observability.sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="$SCRIPT_DIR/../helm"
NAMESPACE="monitoring"

echo -e "${YELLOW}Deploying observability stack...${NC}"
echo "================================"

# Check helm
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm not found${NC}"
    echo "Install: https://helm.sh/docs/intro/install/"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to cluster${NC}"
    exit 1
fi

echo -e "${GREEN}Connected to cluster${NC}"

# Ensure pavan-vps is labeled for monitoring workloads
if ! kubectl get node pavan-vps --show-labels 2>/dev/null | grep -q "workload=monitoring"; then
    echo -e "\n${YELLOW}Labeling pavan-vps with workload=monitoring...${NC}"
    kubectl label node pavan-vps workload=monitoring --overwrite
    echo -e "${GREEN}  Labeled${NC}"
else
    echo -e "\n${GREEN}pavan-vps already labeled workload=monitoring${NC}"
fi

# Add Helm repos
echo -e "\n${YELLOW}Adding Helm repositories...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana-community https://grafana-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update > /dev/null 2>&1
echo -e "${GREEN}  Repositories updated${NC}"

# Create Grafana admin secret if it doesn't exist
if ! kubectl get secret grafana-admin -n monitoring > /dev/null 2>&1; then
    echo -e "\n${YELLOW}Creating Grafana admin secret...${NC}"
    read -rsp "  Enter Grafana admin password: " GRAFANA_ADMIN_PASSWORD; echo
    kubectl -n monitoring create secret generic grafana-admin \
        --from-literal=admin-user=admin \
        --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"
    echo -e "${GREEN}  Secret created${NC}"
else
    echo -e "\n${GREEN}Grafana admin secret already exists${NC}"
fi

# 1. kube-prometheus-stack (Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics)
echo -e "\n${YELLOW}1/3  Deploying kube-prometheus-stack...${NC}"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    -n "$NAMESPACE" \
    -f "$HELM_DIR/prometheus-values.yaml" \
    --timeout 15m
echo -e "${GREEN}  Done${NC}"

# 2. Loki (log storage)
echo -e "\n${YELLOW}2/3  Deploying Loki...${NC}"
helm upgrade --install loki grafana-community/loki \
    -n "$NAMESPACE" \
    -f "$HELM_DIR/loki-values.yaml" \
    --timeout 10m
echo -e "${GREEN}  Done${NC}"

# 3. Alloy (log collector DaemonSet)
echo -e "\n${YELLOW}3/3  Deploying Alloy...${NC}"
helm upgrade --install alloy grafana/alloy \
    -n "$NAMESPACE" \
    -f "$HELM_DIR/alloy-values.yaml" \
    --timeout 10m
echo -e "${GREEN}  Done${NC}"

# Verify
echo -e "\n${YELLOW}Pods:${NC}"
kubectl get pods -n "$NAMESPACE" -o wide

echo -e "\n${YELLOW}PVCs:${NC}"
kubectl get pvc -n "$NAMESPACE"

echo -e "\n${GREEN}================================${NC}"
echo -e "${GREEN}Observability stack deployed!${NC}"
echo ""
echo "Grafana: https://grafana.charana.dev"
echo ""
echo "Verify with: kubectl get pods -n monitoring"
