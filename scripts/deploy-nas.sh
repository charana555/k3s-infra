#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"
SECRETS_DIR="$SCRIPT_DIR/../secrets"

NEXTCLOUD_DIR="$MANIFESTS_DIR/99-apps/nextcloud"
IMMICH_DIR="$MANIFESTS_DIR/99-apps/immich"

echo -e "${YELLOW}Deploying NAS stack (Nextcloud + Immich)...${NC}"
echo "================================"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to cluster${NC}"
    exit 1
fi

echo -e "${GREEN}Connected to cluster${NC}"

apply_file() {
    local file=$1
    echo -e "  Applying: $(basename "$file")"
    if kubectl apply -f "$file" > /dev/null 2>&1; then
        echo -e "${GREEN}    ✓ Success${NC}"
    else
        echo -e "${RED}    ✗ Failed${NC}"
        exit 1
    fi
}

wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-120}
    echo -e "\n${YELLOW}Waiting for $label pods to be ready (timeout: ${timeout}s)...${NC}"
    kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="${timeout}s" 2>/dev/null || {
        echo -e "${YELLOW}  Timeout waiting for pods. Continuing anyway...${NC}"
    }
}

echo -e "\n${YELLOW}Step 3: Deploying shared PostgreSQL...${NC}"
apply_file "$NEXTCLOUD_DIR/postgres-shared.yaml"
apply_file "$NEXTCLOUD_DIR/nextcloud-pvcs.yaml"
wait_for_pods "nas" "app=postgres-shared" 120

echo -e "\n${YELLOW}Step 4: Initializing Nextcloud database...${NC}"
kubectl delete job init-nextcloud-db -n nas 2>/dev/null || true
apply_file "$NEXTCLOUD_DIR/init-nextcloud-db.yaml"
kubectl wait --for=condition=complete job/init-nextcloud-db -n nas --timeout=60s 2>/dev/null || {
    echo -e "${YELLOW}  DB init job may still be running. Check with: kubectl get jobs -n nas${NC}"
}

echo -e "\n${YELLOW}Step 5: Deploying Nextcloud Redis...${NC}"
apply_file "$NEXTCLOUD_DIR/nextcloud-redis.yaml"

echo -e "\n${YELLOW}Step 6: Deploying Nextcloud...${NC}"
apply_file "$NEXTCLOUD_DIR/nextcloud.yaml"
apply_file "$NEXTCLOUD_DIR/nextcloud-cron.yaml"
wait_for_pods "nas" "app=nextcloud" 180

echo -e "\n${YELLOW}Step 7: Deploying Immich PostgreSQL (vectorchord)...${NC}"
apply_file "$IMMICH_DIR/immich-pvcs.yaml"
apply_file "$IMMICH_DIR/immich-postgres.yaml"
wait_for_pods "nas" "app=immich-postgres" 120

echo -e "\n${YELLOW}Step 8: Deploying Immich Redis...${NC}"
apply_file "$IMMICH_DIR/immich-redis.yaml"

echo -e "\n${YELLOW}Step 9: Deploying Immich...${NC}"
apply_file "$IMMICH_DIR/immich-server.yaml"
apply_file "$IMMICH_DIR/immich-microservices.yaml"
wait_for_pods "nas" "app=immich-server" 180

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}NAS stack deployed!${NC}"
echo ""
echo "Nextcloud: https://cloud.charana.dev"
echo "Immich:    https://photos.charana.dev"
