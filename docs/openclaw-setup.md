# OpenClaw Deployment Guide

## Prerequisites

1. Ollama running in cluster with `qwen2.5:7b-instruct-q4_K_M` model pulled
2. Telegram bot token (from [@BotFather](https://t.me/BotFather))
3. kubectl access to the k3s cluster

## Setup Steps

### 1. Deploy Ollama

```bash
kubectl apply -f manifests/99-apps/ollama.yaml
```

Wait for Ollama to be ready:

```bash
kubectl get pods -n apps -l app=ollama -w
```

Pull the model into Ollama:

```bash
kubectl exec -n apps -it deploy/ollama -- ollama pull qwen2.5:7b-instruct-q4_K_M
```

### 2. Create the secrets file

```bash
cp secrets/openclaw-secrets.yaml secrets/openclaw-secrets.local.yaml
```

Edit `secrets/openclaw-secrets.local.yaml` and fill in your actual credentials:

- `gateway-token`: Generate a random token: `openssl rand -hex 32`
- `telegram-bot-token`: From BotFather on Telegram

### 3. Create a Telegram Bot

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` and follow the prompts
3. Copy the bot token to your secrets file

### 4. Apply the secrets

```bash
kubectl apply -f secrets/openclaw-secrets.local.yaml
```

### 5. Apply the OpenClaw manifest

```bash
kubectl apply -f manifests/99-apps/openclaw.yaml
```

### 6. Verify the deployment

```bash
kubectl get pods -n apps -l app=openclaw
kubectl logs -n apps -l app=openclaw --follow
```

### 7. Access the Control UI

Open `https://openclaw.charana.dev` in your browser and enter the gateway token
you set in the secrets.

### 8. Configure Telegram channel

After the pod is running and healthy, configure the Telegram channel:

```bash
kubectl exec -n apps -it deploy/openclaw -- node dist/index.js channels add --channel telegram --token "$TELEGRAM_BOT_TOKEN"
```

Or use the Control UI to add the Telegram channel.

### 9. Pair your Telegram account

Send a message to your bot on Telegram. You will receive a pairing code.
Approve it:

```bash
kubectl exec -n apps -it deploy/openclaw -- node dist/index.js pairing approve telegram <CODE>
```

## Architecture

```
Telegram <--> OpenClaw Gateway <--> Ollama (qwen2.5:7b)
                (apps namespace)       (apps namespace)
                     |
                     v
           Control UI (openclaw.charana.dev)
```

## Configuration

The main config is in the `openclaw-config` ConfigMap (`manifests/99-apps/openclaw.yaml`).

To update configuration:

1. Edit the ConfigMap in the manifest
2. Re-apply: `kubectl apply -f manifests/99-apps/openclaw.yaml`
3. Restart the pod: `kubectl rollout restart deployment/openclaw -n apps`

### Changing Ollama models

1. Pull the new model: `kubectl exec -n apps -it deploy/ollama -- ollama pull <model>`
2. Update the ConfigMap in `manifests/99-apps/openclaw.yaml` with the new model name
3. Apply and restart: `kubectl apply -f manifests/99-apps/openclaw.yaml && kubectl rollout restart deployment/openclaw -n apps`

## Updating

### OpenClaw

```bash
kubectl set image deployment/openclaw openclaw=ghcr.io/openclaw/openclaw:latest -n apps
```

### Ollama

```bash
kubectl set image deployment/ollama ollama=ollama/ollama:latest -n apps
kubectl rollout restart deployment/ollama -n apps
```

## Troubleshooting

### Pod not starting

```bash
kubectl describe pod -n apps -l app=openclaw
kubectl logs -n apps -l app=openclaw --previous
```

### Ollama not responding

```bash
kubectl logs -n apps -l app=ollama --follow
kubectl exec -n apps -it deploy/ollama -- ollama list
```

### Model not found in Ollama

```bash
kubectl exec -n apps -it deploy/ollama -- ollama pull qwen2.5:7b-instruct-q4_K_M
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

| PVC | Namespace | Mount Path | Size | Purpose |
|-----|-----------|-----------|------|---------|
| `openclaw-config` | apps | `/home/node/.openclaw` | 2Gi | Config, auth profiles, installed plugins |
| `openclaw-workspace` | apps | `/home/node/.openclaw/workspace` | 5Gi | Workspace, skills, session data |
| `openclaw-auth-profiles` | apps | `/home/node/.config/openclaw` | 256Mi | Auth profile encryption keys |
| `ollama-data` | apps | `/root/.ollama` | 20Gi | Ollama models and data |

## Security Notes

- The deployment runs as non-root (UID 1000)
- DM pairing is enabled by default for Telegram (`dmPolicy: "pairing"`)
- TLS is auto-provisioned via cert-manager + Let's Encrypt
- Secrets are stored in Kubernetes Secrets (not committed to git)
- The `secrets/` directory is excluded via `.gitignore`
- Ollama is only accessible within the cluster (ClusterIP, no ingress)
