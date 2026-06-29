#!/bin/bash
# Script to create Beszel secrets for the monitoring namespace
# Contains: hub admin credentials + agent TOKEN for auto-registration
# Usage: ./create-beszel-secrets.sh
#
# Two-phase flow:
#   Phase 1 (first run):  Provide admin email + password only.
#                         Token can be left empty - apply the hub, create a
#                         universal token in the UI, then re-run this script.
#   Phase 2 (second run): Provide admin email + password + TOKEN from the hub UI.

set -e

echo "Creating Beszel secrets for monitoring namespace..."
echo ""

# --- Admin credentials ---
read -p "Enter Beszel admin email [admin@charana.dev]: " ADMIN_EMAIL
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@charana.dev}"

read -sp "Enter Beszel admin password: " ADMIN_PASSWORD
echo

# --- Agent registration (universal token) ---
echo ""
echo "Get these from: Beszel Hub -> Add System -> copy the public KEY and TOKEN"
echo "(Leave empty if the hub isn't running yet - re-run this script after creating the token)"
read -p "Enter agent public KEY (optional): " AGENT_KEY
read -p "Enter agent TOKEN (optional): " AGENT_TOKEN

# Create the secret
kubectl create secret generic beszel-secrets \
    --from-literal=admin-email="$ADMIN_EMAIL" \
    --from-literal=admin-password="$ADMIN_PASSWORD" \
    --from-literal=key="${AGENT_KEY:-}" \
    --from-literal=token="${AGENT_TOKEN:-}" \
    --namespace=monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Secret 'beszel-secrets' created/updated in monitoring namespace"
echo ""

if [ -z "$AGENT_KEY" ] || [ -z "$AGENT_TOKEN" ]; then
    echo "=== Phase 1: Hub bootstrap ==="
    echo ""
    echo "Next steps:"
    echo "1. Label the control-plane node:  kubectl label node <oracle-node> workload=monitoring"
    echo "2. Apply the hub:                  kubectl apply -f manifests/03-monitoring/beszel-hub.yaml"
    echo "3. Visit https://beszel.charana.dev (login with admin credentials above)"
    echo "4. Hub UI -> Add System -> copy the public KEY and TOKEN"
    echo "5. Re-run this script with the KEY and TOKEN"
    echo "6. Apply the agent DaemonSet:       kubectl apply -f manifests/03-monitoring/beszel-agent.yaml"
else
    echo "=== Phase 2: Agent deployment ==="
    echo ""
    echo "Next steps:"
    echo "1. Apply the agent DaemonSet:       kubectl apply -f manifests/03-monitoring/beszel-agent.yaml"
    echo "2. Restart agents if already running: kubectl rollout restart daemonset/beszel-agent -n monitoring"
    echo "3. Verify agents registered:       kubectl get pods -n monitoring -l app=beszel-agent -o wide"
    echo "4. Check hub UI - all nodes should appear as systems"
    echo "5. Hub UI -> Notifications -> add Discord webhook"
fi
