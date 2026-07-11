#!/bin/bash
# Script to create Telegram media downloader secrets for media namespace.
# Contains: Telegram API credentials + Bot token + allowed users + Jellyfin API key.
# Usage: ./create-tg-media-secrets.sh
#
# Prerequisites:
#   1. Get api_id and api_hash from https://my.telegram.org -> API development tools
#   2. Create a bot via @BotFather -> /newbot -> copy the token
#   3. Get your Telegram user ID from @userinfobot
#   4. Get Jellyfin API key from Dashboard > Advanced > API Keys
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

# --- Bot token ---
echo ""
echo "Get this from: @BotFather -> /newbot"
read -sp "Enter Telegram Bot Token: " TG_BOT_TOKEN
echo

# --- Allowed users ---
echo ""
echo "Get this from: @userinfobot (your numeric Telegram user ID)"
echo "Multiple users: comma-separated, e.g. 123456789,987654321"
read -p "Enter allowed user IDs: " TG_ALLOWED_USERS

# --- Jellyfin API key ---
echo ""
echo "Get this from: Jellyfin Dashboard > Advanced > API Keys"
read -sp "Enter Jellyfin API key: " JELLYFIN_API_KEY
echo

kubectl create secret generic tg-media-secrets \
    --from-literal=TELEGRAM_API_ID="$TG_API_ID" \
    --from-literal=TELEGRAM_API_HASH="$TG_API_HASH" \
    --from-literal=TELEGRAM_BOT_TOKEN="$TG_BOT_TOKEN" \
    --from-literal=TELEGRAM_ALLOWED_USERS="$TG_ALLOWED_USERS" \
    --from-literal=JELLYFIN_API_KEY="$JELLYFIN_API_KEY" \
    --namespace=media \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Secret 'tg-media-secrets' created/updated in media namespace"
echo ""
echo "Next steps:"
echo "1. Apply:            kubectl apply -f manifests/99-apps/media/tg-media.yaml"
echo "2. First-time login: kubectl exec -it deploy/tg-media -n media -- python /app/tg-media.py login"
echo "3. Restart pod:      kubectl rollout restart deployment tg-media -n media"
echo "4. Send /help to your bot in Telegram"
