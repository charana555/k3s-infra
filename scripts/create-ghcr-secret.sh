#!/bin/bash
# Script to create GHCR image pull secret for Portfolio V2
# Usage: ./create-ghcr-secret.sh

set -e

echo "Creating GHCR credentials secret for apps namespace..."

# Prompt for GitHub credentials
read -p "Enter your GitHub username: " GITHUB_USERNAME
read -sp "Enter your GitHub Personal Access Token (with read:packages scope): " GITHUB_TOKEN
echo

# Create the secret
kubectl create secret docker-registry ghcr-credentials \
    --docker-server=ghcr.io \
    --docker-username="$GITHUB_USERNAME" \
    --docker-password="$GITHUB_TOKEN" \
    --namespace=apps \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secret 'ghcr-credentials' created in apps namespace"
echo ""
echo "Next steps:"
echo "1. Apply the namespace: kubectl apply -f manifests/00-namespace/namespace.yaml"
echo "2. Apply the portfolio deployment: kubectl apply -f manifests/99-apps/portfolio-v2.yaml"
echo "3. Verify: kubectl get pods -n apps"
