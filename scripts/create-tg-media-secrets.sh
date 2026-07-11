#!/bin/bash
# Script to create Telegram media downloader secrets for media namespace.
# Contains: Telegram API credentials + Jellyfin API key.
# Usage: ./create-tg-media-secrets.sh
#
# Prerequisites:
#   1. Get api_id and api_hash from https://my.telegram.org -> API development tools
#   2. Get Jellyfin API key from Dashboard > Advanced > API Keys
#
# First-time login is interactive and done after deployment:
#   kubectl exec -it deploy/tg-media -n media -- python /app/tg-media.py login

set -e

echo "Creating tg-media secrets for media namespace..."
echo ""

# --- Telegram API credentials ---
echo "Get these from: https://my.telegram.org -> API development tools"
read -p "Enter Telegram API ID: " TG_API_ID
read -sp "Enter Telegram API Hash: " TG_API_HASH
echo

# --- Jellyfin API key ---
echo ""
echo "Get this from: Jellyfin Dashboard > Advanced > API Keys"
read -sp "Enter Jellyfin API key: " JELLYFIN_API_KEY
echo

kubectl create secret generic tg-media-secrets \
    --from-literal=TELEGRAM_API_ID="$TG_API_ID" \
    --from-literal=TELEGRAM_API_HASH="$TG_API_HASH" \
    --from-literal=JELLYFIN_API_KEY="$JELLYFIN_API_KEY" \
    --namespace=media \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Secret 'tg-media-secrets' created/updated in media namespace"
echo ""
echo "Next steps:"
echo "1. Apply the deployment: kubectl apply -f manifests/99-apps/media/tg-media.yaml"
echo "2. First-time login:      kubectl exec -it deploy/tg-media -n media -- python /app/tg-media.py login"
echo "3. List chats:            kubectl exec -it deploy/tg-media -n media -- python /app/tg-media.py chats"
echo "4. Download:              kubectl exec -it deploy/tg-media -n media -- python /app/tg-media.py download @SomeBot latest"
