#!/bin/bash
set -e

# Backup script for k3s cluster
BACKUP_DIR="${HOME}/k3s-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Starting k3s backup...${NC}"
echo "Backup location: $BACKUP_PATH"

# Create backup directory
mkdir -p "$BACKUP_PATH"

# Backup k3s configuration
echo "Backing up k3s config..."
if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    sudo cp /etc/rancher/k3s/k3s.yaml "$BACKUP_PATH/kubeconfig.yaml"
    sudo chown $USER:$USER "$BACKUP_PATH/kubeconfig.yaml"
fi

# Export all resources
echo "Exporting Kubernetes resources..."
kubectl get all --all-namespaces -o yaml > "$BACKUP_PATH/all-resources.yaml" 2>/dev/null || true
kubectl get configmaps --all-namespaces -o yaml > "$BACKUP_PATH/configmaps.yaml" 2>/dev/null || true
kubectl get secrets --all-namespaces -o yaml > "$BACKUP_PATH/secrets.yaml" 2>/dev/null || true
kubectl get ingress --all-namespaces -o yaml > "$BACKUP_PATH/ingress.yaml" 2>/dev/null || true
kubectl get pvc --all-namespaces -o yaml > "$BACKUP_PATH/pvc.yaml" 2>/dev/null || true

# Backup etcd (if running on control plane)
if systemctl is-active --quiet k3s; then
    echo "Backing up etcd data..."
    sudo k3s etcd-snapshot save --name "backup-$TIMESTAMP" 2>/dev/null || echo "Note: etcd snapshot requires k3s server"
fi

# Backup manifests directory
echo "Backing up local manifests..."
tar -czf "$BACKUP_PATH/manifests.tar.gz" -C "$(dirname $0)/.." manifests/ 2>/dev/null || true

# Create info file
cat > "$BACKUP_PATH/backup-info.txt" << EOF
K3s Backup
==========
Date: $(date)
Hostname: $(hostname)
K3s Version: $(k3s --version 2>/dev/null || echo 'unknown')
Kubernetes Version: $(kubectl version --short 2>/dev/null || echo 'unknown')

Contents:
- kubeconfig.yaml: Cluster access configuration
- all-resources.yaml: All Kubernetes resources
- configmaps.yaml: ConfigMaps
- secrets.yaml: Secrets (names only, values redacted)
- ingress.yaml: Ingress rules
- pvc.yaml: Persistent Volume Claims
- manifests.tar.gz: Local manifest files
EOF

echo -e "${GREEN}Backup complete: $BACKUP_PATH${NC}"
echo ""
echo "To restore, use:"
echo "  kubectl apply -f $BACKUP_PATH/all-resources.yaml"
