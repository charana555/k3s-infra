#!/bin/bash
# Create OmniRoute secrets with encryption keys
# Usage: ./scripts/create-omniroute-secrets.sh

set -e

echo "=== OmniRoute Secret Generator ==="
echo ""
echo "This script creates the omniroute-encryption secret in the apps namespace."
echo "The encryption key secures provider credentials (API keys, OAuth tokens) at rest."
echo ""
echo "⚠️  CRITICAL: Back up the generated key securely (password manager, KMS)."
echo "   Losing the key means losing access to ALL provider credentials."
echo ""

# Check if secret already exists
if kubectl get secret omniroute-encryption -n apps >/dev/null 2>&1; then
  echo "❌ Secret 'omniroute-encryption' already exists in namespace 'apps'"
  echo ""
  read -p "Do you want to REPLACE it? This will break existing encrypted data! (yes/no): " confirm
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

echo "✅ Generated 256-bit encryption key"
echo ""

# Display the key (user should save it)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 STORAGE ENCRYPTION KEY (save this securely!):"
echo ""
echo "$STORAGE_KEY"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💾 Save this key in a secure location:"
echo "   - Password manager (1Password, Bitwarden, etc.)"
echo "   - KMS (AWS Secrets Manager, Google Secret Manager, etc.)"
echo "   - Encrypted backup (NOT in Git)"
echo ""

read -p "Press ENTER when you have saved the key securely..."
echo ""

# Create the secret
echo "📦 Creating Kubernetes secret..."
kubectl create secret generic omniroute-encryption \
  -n apps \
  --from-literal=storage-encryption-key="$STORAGE_KEY"

if [ $? -eq 0 ]; then
  echo "✅ Secret 'omniroute-encryption' created successfully in namespace 'apps'"
  echo ""
  echo "Next steps:"
  echo "  1. Deploy OmniRoute: kubectl apply -f manifests/99-apps/omniroute.yaml"
  echo "  2. Verify deployment: kubectl get pods -n apps -l app=omniroute"
  echo "  3. Check logs: kubectl logs -n apps -l app=omniroute -f"
  echo "  4. Access dashboard: https://omniroute.charana.dev (Tailscale only)"
  echo ""
  echo "🔐 Backup strategy:"
  echo "  - Database: kubectl exec -n apps deployment/omniroute -- sqlite3 /app/data/storage.sqlite \".backup /app/data/backup.sqlite\""
  echo "  - Encryption key: Already displayed above (make sure you saved it!)"
else
  echo "❌ Failed to create secret"
  exit 1
fi
