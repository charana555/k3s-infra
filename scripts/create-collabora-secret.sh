#!/bin/bash
# Script to create Collabora admin secret for nas namespace
# Usage: ./create-collabora-secret.sh

set -e

echo "Creating Collabora admin secret for nas namespace..."

read -p "Enter Collabora admin username: " COLLABORA_USERNAME
read -sp "Enter Collabora admin password: " COLLABORA_PASSWORD
echo

kubectl create secret generic collabora-admin-secret \
    --from-literal=username="$COLLABORA_USERNAME" \
    --from-literal=password="$COLLABORA_PASSWORD" \
    --namespace=nas \
    --dry-run=client -o yaml | kubectl apply -f -

echo "Secret 'collabora-admin-secret' created in nas namespace"
echo ""
echo "Next steps:"
echo "1. Apply the namespace: kubectl apply -f manifests/00-namespace/namespace.yaml"
echo "2. Apply the Collabora deployment: kubectl apply -f manifests/04-nas/collabora.yaml"
echo "3. Verify: kubectl get pods -n nas"
echo "4. In Nextcloud, install the Nextcloud Office app and set WOPI URL to https://office.charana.dev"
