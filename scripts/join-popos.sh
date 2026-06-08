#!/bin/bash
set -euo pipefail

# =============================================================================
# K3s Worker Node Join Script for Pop!_OS Laptop (LLM/GPU Node)
# =============================================================================
# Usage: ./join-popos.sh <oracle-control-plane-tailscale-ip> [node-name]
#
# Prerequisites:
#   - Tailscale installed and connected
#   - NVIDIA drivers installed (nvidia-smi should work)
#   - NVIDIA Container Toolkit installed
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
K3s Pop!_OS LLM Node Join Script

Usage:
  $0 <oracle-control-plane-tailscale-ip> [node-name]

Arguments:
  oracle-control-plane-tailscale-ip   Tailscale IP of Oracle control plane
  node-name                          Name for this node (default: popos-llm)

Examples:
  $0 100.64.0.1
  $0 100.64.0.1 my-gpu-node

Prerequisites:
  - Tailscale installed and connected
  - NVIDIA GPU drivers installed
  - NVIDIA Container Toolkit configured for containerd
  - SSH access to Oracle node for retrieving token

EOF
    exit 0
}

# Parse arguments
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

CONTROL_PLANE_IP="$1"
NODE_NAME="${2:-popos-llm}"
K3S_URL="https://${CONTROL_PLANE_IP}:6443"
ORACLE_USER="ubuntu"

echo -e "${BOLD}K3s Pop!_OS LLM Node Join${NC}\n"

# Validate prerequisites
log_info "Checking prerequisites..."

# Check if we're running as root
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

# Check NVIDIA drivers
if ! command -v nvidia-smi &> /dev/null; then
    log_error "NVIDIA drivers not found. Install them first:"
    echo "  sudo apt update"
    echo "  sudo apt install -y nvidia-driver-XXX nvidia-utils-XXX"
    exit 1
fi

GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null)
if [ -z "$GPU_INFO" ]; then
    log_error "NVIDIA GPU not detected. Check nvidia-smi output."
    exit 1
fi
log_success "GPU detected: ${GPU_INFO}"

# Check NVIDIA Container Toolkit
if ! command -v nvidia-ctk &> /dev/null; then
    log_warn "NVIDIA Container Toolkit not found. Installing..."
    
    distribution=$(. /etc/os-release; echo "$ID$VERSION_ID")
    
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | \
        sudo apt-key add - 2>/dev/null || {
            log_error "Failed to add NVIDIA repository GPG key"
            exit 1
        }
    
    curl -s -L "https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list" | \
        sudo tee /etc/apt/sources.list.d/nvidia-docker.list
    
    sudo apt update
    sudo apt install -y nvidia-container-toolkit
    
    # Configure containerd runtime
    sudo nvidia-ctk runtime configure --runtime=containerd
    
    if systemctl is-active --quiet containerd 2>/dev/null; then
        sudo systemctl restart containerd
    fi
    
    log_success "NVIDIA Container Toolkit installed"
else
    log_success "NVIDIA Container Toolkit is available"
    
    # Verify containerd runtime is configured
    if [ -f /etc/containerd/config.toml ] && grep -q "nvidia-container-runtime" /etc/containerd/config.toml; then
        log_success "Containerd runtime configured for NVIDIA"
    else
        log_warn "Configuring containerd runtime for NVIDIA..."
        sudo nvidia-ctk runtime configure --runtime=containerd
        if systemctl is-active --quiet containerd 2>/dev/null; then
            sudo systemctl restart containerd
        fi
    fi
fi

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

# Wait for node to be ready
echo ""
log_info "Waiting for node to register..."
sleep 10

for i in {1..12}; do
    if kubectl get nodes "$NODE_NAME" &> /dev/null; then
        NODE_STATUS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[-1:].status}' 2>/dev/null)
        if [ "$NODE_STATUS" = "True" ]; then
            log_success "Node ${NODE_NAME} is Ready"
            break
        fi
    fi
    echo -n "."
    sleep 5
done

if ! kubectl get nodes "$NODE_NAME" &> /dev/null; then
    log_warn "Node not yet visible. Check manually with:"
    echo "  kubectl get nodes"
fi

# Install NVIDIA device plugin
echo ""
log_info "Installing NVIDIA device plugin for GPU scheduling..."
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.5/nvidia-device-plugin.yml

log_success "NVIDIA device plugin deployed"

# Verify GPU is allocatable
echo ""
log_info "Verifying GPU allocation..."
sleep 5

GPU_ALLOCATABLE=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null)
if [ -n "$GPU_ALLOCATABLE" ] && [ "$GPU_ALLOCATABLE" != "" ]; then
    log_success "GPU is allocatable: ${GPU_ALLOCATABLE} device(s)"
else
    log_warn "GPU not yet visible as allocatable. This may take a minute."
    log_info "Check with: kubectl describe node ${NODE_NAME} | grep -i nvidia"
fi

echo ""
log_info "Next steps (run these on the control plane):"
echo ""
echo -e "  ${BOLD}1. Label the node:${NC}"
echo "     kubectl label node ${NODE_NAME} nvidia.com/gpu.present=true workload=llm"
echo ""
echo -e "  ${BOLD}2. Taint the node (prevents other workloads):${NC}"
echo "     kubectl taint node ${NODE_NAME} dedicated=llm:NoSchedule"
echo ""
echo -e "  ${BOLD}3. Verify GPU scheduling works:${NC}"
echo "     kubectl describe node ${NODE_NAME} | grep -A5 Allocatable"
echo ""
echo -e "  ${BOLD}4. Ollama will automatically schedule here when:${NC}"
echo "     - This node is online and Ready"
echo "     - Ollama deployment is restarted or updated"
echo ""

log_success "Pop!_OS LLM node setup complete!"
log_info "Power off this laptop anytime - Ollama will wait until you come back online."
