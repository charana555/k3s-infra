#!/bin/bash
# Script to create SFTPGo secrets for the nas namespace.
# Contains: initial WebAdmin credentials for each per-node instance.
# Usage: ./create-sftpgo-secrets.sh
#
# Deliberately no template in manifests/ (same pattern as
# collabora-admin-secret): the Secret is not tracked by ArgoCD, so
# self-heal can never revert real credentials to placeholders.
#
# The credentials only seed the FIRST admin on first start of each
# instance (SQLite is empty). If an admin already exists, SFTPGo
# ignores these values - rotate passwords via the WebAdmin UI.
# Until the secrets exist, the sftpgo pods stay in
# CreateContainerConfigError (fail-closed).

set -e

echo "Creating SFTPGo secrets for nas namespace..."
echo ""

create_secret() {
    local NODE=$1
    local SECRET_NAME=$2

    read -p "Enter admin username for ${NODE} instance: " ADMIN_USERNAME
    ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"

    read -sp "Enter admin password for ${NODE} instance: " ADMIN_PASSWORD
    echo

    kubectl create secret generic "${SECRET_NAME}" \
        --from-literal=admin-username="${ADMIN_USERNAME}" \
        --from-literal=admin-password="${ADMIN_PASSWORD}" \
        --namespace=nas \
        --dry-run=client -o yaml | kubectl apply -f -

    echo ""
    echo "Secret '${SECRET_NAME}' created/updated in nas namespace"
    echo ""
}

create_secret "charana-vps (cvps.charana.dev)" "sftpgo-secrets-charana"
create_secret "pavan-vps (pvps.charana.dev)" "sftpgo-secrets-pavan"

echo "Next steps:"
echo "1. Apply the manifests (or merge to main and let ArgoCD sync):"
echo "   kubectl apply -f manifests/99-apps/sftpgo/"
echo "2. Pods start once the secrets exist; verify:"
echo "   kubectl -n nas get pods -l app=sftpgo-charana -o wide"
echo "3. Visit https://cvps.charana.dev/web/admin and https://pvps.charana.dev/web/admin"
echo "4. In each WebAdmin, create a user with home dir /srv/storage to browse /mnt/data"
