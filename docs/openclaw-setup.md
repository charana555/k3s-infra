# OpenClaw Deployment Guide

## Prerequisites

1. AWS Bedrock access with `kimi-latest` model enabled (bearer token auth)
2. Telegram bot token (from [@BotFather](https://t.me/BotFather))
3. kubectl access to the k3s cluster

## Setup Steps

### 1. Create the secrets file

```bash
cp secrets/openclaw-secrets.yaml secrets/openclaw-secrets.local.yaml
```

Edit `secrets/openclaw-secrets.local.yaml` and fill in your actual credentials:

- `aws-bearer-token-bedrock`: Your AWS Bedrock bearer token
- `aws-region`: AWS region for Bedrock (e.g., `ap-south-1`)
- `gateway-token`: Generate a random token: `openssl rand -hex 32`
- `telegram-bot-token`: From BotFather on Telegram

### 2. Create a Telegram Bot

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` and follow the prompts
3. Copy the bot token to your secrets file

### 3. Apply the secrets

```bash
kubectl apply -f secrets/openclaw-secrets.local.yaml
```

### 4. Apply the manifests

```bash
kubectl apply -f manifests/99-apps/openclaw.yaml
```

### 5. Verify the deployment

```bash
kubectl get pods -n apps -l app=openclaw
kubectl logs -n apps -l app=openclaw --follow
```

### 6. Access the Control UI

Open `https://openclaw.charana.dev` in your browser and enter the gateway token
you set in the secrets.

### 7. Configure Telegram channel

After the pod is running and healthy, configure the Telegram channel:

```bash
# Exec into the running pod
kubectl exec -n apps -it deploy/openclaw -- node dist/index.js channels add --channel telegram --token "$TELEGRAM_BOT_TOKEN"
```

Or use the Control UI to add the Telegram channel.

### 8. Pair your Telegram account

Send a message to your bot on Telegram. You will receive a pairing code.
Approve it:

```bash
kubectl exec -n apps -it deploy/openclaw -- node dist/index.js pairing approve telegram <CODE>
```

## Configuration

The main config is in the `openclaw-config` ConfigMap (`manifests/99-apps/openclaw.yaml`).

To update configuration:

1. Edit the ConfigMap in the manifest
2. Re-apply: `kubectl apply -f manifests/99-apps/openclaw.yaml`
3. Restart the pod: `kubectl rollout restart deployment/openclaw -n apps`

## Updating

```bash
# Pull the latest image
kubectl set image deployment/openclaw openclaw=ghcr.io/openclaw/openclaw:latest -n apps

# Or pin a specific version
kubectl set image deployment/openclaw openclaw=ghcr.io/openclaw/openclaw:2026.5.14 -n apps
```

## Troubleshooting

### Pod not starting

```bash
kubectl describe pod -n apps -l app=openclaw
kubectl logs -n apps -l app=openclaw --previous
```

### Permission errors on PVC

The init container should fix permissions automatically. If issues persist:

```bash
kubectl exec -n apps -it deploy/openclaw -- ls -la /home/node/.openclaw
```

### Telegram not connecting

```bash
kubectl exec -n apps -it deploy/openclaw -- node dist/index.js doctor
```

### Health check failures

```bash
kubectl exec -n apps -it deploy/openclaw -- curl -s http://localhost:18789/healthz
kubectl exec -n apps -it deploy/openclaw -- curl -s http://localhost:18789/readyz
```

## Storage

| PVC | Mount Path | Size | Purpose |
|-----|-----------|------|---------|
| `openclaw-config` | `/home/node/.openclaw` | 2Gi | Config, auth profiles, installed plugins |
| `openclaw-workspace` | `/home/node/.openclaw/workspace` | 5Gi | Workspace, skills, session data |
| `openclaw-auth-profiles` | `/home/node/.config/openclaw` | 256Mi | Auth profile encryption keys |

## Security Notes

- The deployment runs as non-root (UID 1000)
- DM pairing is enabled by default for Telegram (`dmPolicy: "pairing"`)
- TLS is auto-provisioned via cert-manager + Let's Encrypt
- Secrets are stored in Kubernetes Secrets (not committed to git)
- The `secrets/` directory is excluded via `.gitignore`
