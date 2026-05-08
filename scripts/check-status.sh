#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}      K3s Cluster Status Report${NC}"
echo -e "${BLUE}========================================${NC}"

# Check cluster connectivity
echo -e "\n${YELLOW}Cluster Connection:${NC}"
if kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Connected${NC}"
    kubectl cluster-info | grep "Kubernetes control plane"
else
    echo -e "${RED}✗ Not connected${NC}"
    exit 1
fi

# Nodes
echo -e "\n${YELLOW}Nodes:${NC}"
kubectl get nodes -o wide

# Namespaces
echo -e "\n${YELLOW}Namespaces:${NC}"
kubectl get namespaces

# Pods (excluding kube-system for brevity)
echo -e "\n${YELLOW}User Pods (non-system):${NC}"
kubectl get pods --all-namespaces --field-selector metadata.namespace!=kube-system

# All pods (full list)
echo -e "\n${YELLOW}System Pods (kube-system):${NC}"
kubectl get pods -n kube-system

# Deployments
echo -e "\n${YELLOW}Deployments:${NC}"
kubectl get deployments --all-namespaces

# Services
echo -e "\n${YELLOW}Services:${NC}"
kubectl get services --all-namespaces | grep -v "ClusterIP.*None"

# Ingress
echo -e "\n${YELLOW}Ingress Rules:${NC}"
kubectl get ingress --all-namespaces 2>/dev/null || echo "No ingress resources found"

# Resource usage (if metrics-server is running)
echo -e "\n${YELLOW}Resource Usage:${NC}"
if kubectl top nodes > /dev/null 2>&1; then
    echo "Nodes:"
    kubectl top nodes
    echo ""
    echo "Pods (top 10 by CPU):"
    kubectl top pods --all-namespaces --sort-by=cpu | head -11
else
    echo -e "${YELLOW}Metrics server not available${NC}"
fi

# Recent events
echo -e "\n${YELLOW}Recent Events (Warnings):${NC}"
kubectl get events --field-selector type=Warning --sort-by='.lastTimestamp' | tail -5

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}Status check complete${NC}"
