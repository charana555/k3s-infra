#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

echo -e "${YELLOW}Applying k3s manifests...${NC}"
echo "================================"

# Function to apply manifests in a directory
apply_dir() {
    local dir=$1
    local name=$2
    
    if [ -d "$dir" ]; then
        echo -e "\n${YELLOW}Applying $name...${NC}"
        
        # Find and sort YAML files
        files=$(find "$dir" -name "*.yaml" -o -name "*.yml" | sort)
        
        if [ -z "$files" ]; then
            echo -e "${YELLOW}  No YAML files found in $dir${NC}"
            return
        fi
        
        # Apply each file
        while IFS= read -r file; do
            echo -e "  Applying: $(basename "$file")"
            if kubectl apply -f "$file" > /dev/null 2>&1; then
                echo -e "${GREEN}    ✓ Success${NC}"
            else
                echo -e "${RED}    ✗ Failed${NC}"
                exit 1
            fi
        done <<< "$files"
    fi
}

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to cluster${NC}"
    echo "Please ensure k3s is running and kubeconfig is set"
    exit 1
fi

echo -e "${GREEN}Connected to cluster${NC}"
echo ""

# Apply in order
apply_dir "$MANIFESTS_DIR/00-namespace" "Namespaces"
apply_dir "$MANIFESTS_DIR/01-networking" "Networking"
apply_dir "$MANIFESTS_DIR/02-storage" "Storage"
apply_dir "$MANIFESTS_DIR/03-monitoring" "Monitoring"
apply_dir "$MANIFESTS_DIR/04-nas" "NAS"
apply_dir "$MANIFESTS_DIR/05-llm" "LLM"
apply_dir "$MANIFESTS_DIR/06-backup" "Backup"
apply_dir "$MANIFESTS_DIR/99-apps" "Applications"

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}All manifests applied successfully!${NC}"
echo ""
echo "Run './scripts/check-status.sh' to verify deployment"
