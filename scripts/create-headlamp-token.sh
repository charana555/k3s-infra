#!/bin/bash
# Script to retrieve (or mint) a Headlamp login token for the monitoring namespace.
# Headlamp authenticates with a ServiceAccount bearer token; paste it into the
# Headlamp login screen at https://headlamp.charana.dev
#
# Usage: ./scripts/create-headlamp-token.sh
#
# Prerequisites:
#   kubectl apply -f manifests/03-monitoring/headlamp-rbac.yaml
#   kubectl apply -f manifests/03-monitoring/headlamp.yaml

set -e

echo "Retrieving Headlamp login token for monitoring namespace..."
echo ""

TOKEN=""

# 1. Try the long-lived Secret created by headlamp-rbac.yaml.
#    On K8s < 1.33 the token controller auto-populates .data.token.
if kubectl get secret headlamp-admin -n monitoring >/dev/null 2>&1; then
    TOKEN=$(kubectl get secret headlamp-admin -n monitoring -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi

# 2. Fall back to minting a token directly (K8s 1.24+; works on 1.33+ where
#    auto-populated Secret tokens are no longer supported by default).
if [ -z "$TOKEN" ]; then
    echo "Long-lived Secret token not available; minting a 1-year token via 'kubectl create token'..."
    TOKEN=$(kubectl create token headlamp-admin -n monitoring --duration=8760h)
fi

if [ -z "$TOKEN" ]; then
    echo "Error: could not retrieve a token. Ensure headlamp-rbac.yaml is applied." >&2
    exit 1
fi

echo "==========================================================="
echo " Headlamp login token (copy the line below):"
echo "==========================================================="
echo ""
echo "$TOKEN"
echo ""
echo "==========================================================="
echo ""
echo "Next steps:"
echo "1. Apply the manifests (if not done):"
echo "   kubectl apply -f manifests/03-monitoring/headlamp-rbac.yaml"
echo "   kubectl apply -f manifests/03-monitoring/headlamp.yaml"
echo "2. Verify the pod is running:"
echo "   kubectl get pods -n monitoring -l app=headlamp"
echo "3. Visit https://headlamp.charana.dev"
echo "4. Choose 'Bearer token' access and paste the token above."
echo ""
echo "Note: 'kubectl create token' minted tokens expire (this one in ~1 year)."
echo "      For a long-lived token, ensure headlamp-rbac.yaml's Secret is"
echo "      auto-populated by the token controller (K8s < 1.33)."
