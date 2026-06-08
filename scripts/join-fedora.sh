#!/bin/bash
set -euo pipefail

# =============================================================================
# K3s Worker Node Join Script for Fedora Laptop (Backup Node)
# =============================================================================
# Usage: ./join-fedora.sh <oracle-control-plane-tailscale-ip> [node-name]
#
# Prerequisites:
#   - Tailscale installed and connected
#   - 1TB drive mounted at /mnt/backup
#   - Restic installed
#   - SSH access to Oracle control plane node
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

show_help() {
    cat << EOF
K3s Fedora Backup Node Join Script

Usage:
  $0 <oracle-control-plane-tailscale-ip> [node-name]

Arguments:
  oracle-control-plane-tailscale-ip   Tailscale IP of Oracle control plane
  node-name                          Name for this node (default: fedora-backup)

Examples:
  $0 100.64.0.1
  $0 100.64.0.1 my-backup-node

Prerequisites:
  - Tailscale installed and connected
  - 1TB drive mounted at /mnt/backup
  - Restic installed: sudo dnf install restic
  - SSH access to Oracle node for retrieving token

EOF
    exit 0
}

# Parse arguments
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

CONTROL_PLANE_IP="$1"
NODE_NAME="${2:-fedora-backup}"
K3S_URL="https://${CONTROL_PLANE_IP}:6443"
ORACLE_USER="ubuntu"

echo -e "${BOLD}K3s Fedora Backup Node Join${NC}\n"

# Validate prerequisites
log_info "Checking prerequisites..."

# Check if we're running as root (don't want that for kubectl later)
if [ "$EUID" -eq 0 ]; then
    log_warn "Running as root. Continuing but note kubectl commands will need sudo."
fi

# Check Tailscale connection
if ! command -v tailscale &> /dev/null; then
    log_error "Tailscale not installed. Install it first:"
    echo "  curl -fsSL https://tailscale.com/install.sh | sh"
    exit 1
fi

if ! tailscale status &> /dev/null; then
    log_error "Tailscale not connected. Run: sudo tailscale up"
    exit 1
fi
log_success "Tailscale is connected"

# Check backup mount
if [ ! -d "/mnt/backup" ]; then
    log_warn "/mnt/backup directory not found. Creating..."
    sudo mkdir -p /mnt/backup
fi

if ! mountpoint -q /mnt/backup 2>/dev/null; then
    log_warn "/mnt/backup is not a mounted filesystem."
    log_info "Please mount your 1TB drive before proceeding:"
    echo "  sudo mount /dev/sdX1 /mnt/backup"
    echo "  # Add to /etc/fstab for persistence"
    read -p "Continue anyway? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
log_success "Backup directory ready"

# Check restic
if ! command -v restic &> /dev/null; then
    log_warn "Restic not installed. Installing..."
    sudo dnf install -y restic
fi
log_success "Restic is available"

# Check if k3s-agent is already running
if systemctl is-active --quiet k3s-agent 2>/dev/null; then
    log_warn "k3s-agent is already running on this machine"
    read -p "Rejoin cluster? This will reset the node. [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        exit 0
    fi
    log_info "Stopping existing k3s-agent..."
    sudo systemctl stop k3s-agent
    sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s/agent
fi

# Retrieve token from Oracle control plane
echo ""
log_info "Retrieving k3s join token from control plane..."
read -p "SSH user for Oracle node [${ORACLE_USER}]: " ssh_user
SSH_USER="${ssh_user:-$ORACLE_USER}"

read -p "SSH key path [~/.ssh/id_rsa]: " ssh_key
SSH_KEY="${ssh_key:-$HOME/.ssh/id_rsa}"

if [ ! -f "$SSH_KEY" ]; then
    log_error "SSH key not found: $SSH_KEY"
    exit 1
fi

TOKEN=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 "${SSH_USER}@${CONTROL_PLANE_IP}" "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    log_error "Failed to retrieve token from control plane"
    log_info "Alternative: Get the token manually with:"
    echo "  ssh ${SSH_USER}@${CONTROL_PLANE_IP} 'sudo cat /var/lib/rancher/k3s/server/node-token'"
    read -p "Paste token here: " TOKEN
    if [ -z "$TOKEN" ]; then
        log_error "No token provided. Exiting."
        exit 1
    fi
fi

log_success "Token retrieved successfully"

# Join cluster
echo ""
log_info "Joining k3s cluster..."
log_info "Node name: ${NODE_NAME}"
log_info "Control plane: ${K3S_URL}"

curl -sfL https://get.k3s.io | \
    K3S_URL="$K3S_URL" \
    K3S_TOKEN="$TOKEN" \
    K3S_NODE_NAME="$NODE_NAME" \
    sh -

log_success "Node joined cluster successfully"

# Verify node is registered
echo ""
log_info "Verifying node registration..."
sleep 5

if kubectl get nodes "$NODE_NAME" &> /dev/null; then
    log_success "Node ${NODE_NAME} is registered"
else
    log_warn "Node not yet visible in kubectl. Waiting 10 more seconds..."
    sleep 10
    if kubectl get nodes "$NODE_NAME" &> /dev/null; then
        log_success "Node ${NODE_NAME} is now registered"
    else
        log_warn "Could not verify node registration. Check manually with:"
        echo "  kubectl get nodes"
    fi
fi

echo ""
log_info "Next steps (run these on the control plane):"
echo ""
echo -e "  ${BOLD}1. Label the node:${NC}"
echo "     kubectl label node ${NODE_NAME} workload=backup storage=local-1tb"
echo ""
echo -e "  ${BOLD}2. Taint the node (prevents other workloads):${NC}"
echo "     kubectl taint node ${NODE_NAME} dedicated=backup:NoSchedule"
echo ""
echo -e "  ${BOLD}3. Verify node is Ready:${NC}"
echo "     kubectl get nodes -o wide"
echo ""
echo -e "  ${BOLD}4. Apply backup manifests:${NC}"
echo "     kubectl apply -f manifests/06-backup/"
echo ""
echo -e "  ${BOLD}5. Create restic password secret:${NC}"
echo "     kubectl create secret generic restic-password \\"
echo "       --from-literal=password=YOUR_STRONG_PASSWORD \\"
echo "       -n backup"
echo ""

log_success "Fedora backup node setup complete!"
