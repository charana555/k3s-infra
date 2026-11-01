#!/bin/bash
# Create OmniRoute secrets with encryption keys and initial password
# Usage: ./scripts/create-omniroute-secrets.sh

set -e

echo "=== OmniRoute Secret & Password Generator ==="
echo ""
echo "This script creates the omniroute-encryption secret in the apps namespace."
echo "It includes:"
echo "  1. Storage encryption key (AES-256-GCM for credentials at rest)"
echo "  2. Initial admin password (bypasses loopback check when behind reverse proxy)"
echo ""

# Check if secret already exists
if kubectl get secret omniroute-encryption -n apps >/dev/null 2>&1; then
  echo "❌ Secret 'omniroute-encryption' already exists in namespace 'apps'"
  echo ""
  read -p "Do you want to REPLACE it? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
  fi
  echo ""
  echo "Deleting existing secret..."
  kubectl delete secret omniroute-encryption -n apps
fi

# Generate encryption key
echo "🔐 Generating AES-256-GCM encryption key..."
STORAGE_KEY=$(openssl rand -hex 32)

if [ -z "$STORAGE_KEY" ]; then
  echo "❌ Failed to generate encryption key"
  exit 1
fi

# Prompt for initial password or generate one
echo ""
read -p "Enter initial admin password (leave blank to auto-generate): " INITIAL_PASS
if [ -z "$INITIAL_PASS" ]; then
  INITIAL_PASS=$(openssl rand -base64 16)
  echo "Generated random initial password: $INITIAL_PASS"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 STORAGE ENCRYPTION KEY (save securely!):"
echo "$STORAGE_KEY"
echo ""
echo "👤 INITIAL ADMIN PASSWORD (use this to log in behind Traefik):"
echo "$INITIAL_PASS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Press ENTER when you have saved both credentials securely..."
echo ""

# Create the secret with both keys
echo "📦 Creating Kubernetes secret..."
kubectl create secret generic omniroute-encryption \
  -n apps \
  --from-literal=storage-encryption-key="$STORAGE_KEY" \
  --from-literal=initial-password="$INITIAL_PASS"

if [ $? -eq 0 ]; then
  echo "✅ Secret 'omniroute-encryption' created successfully in namespace 'apps'"
  echo ""
  echo "Next steps:"
  echo "  1. Restart/apply OmniRoute: kubectl apply -f manifests/99-apps/omniroute.yaml && kubectl rollout restart deployment/omniroute -n apps"
  echo "  2. Access dashboard: https://omniroute.charana.dev and log in using the initial password above."
else
  echo "❌ Failed to create secret"
  exit 1
fi
