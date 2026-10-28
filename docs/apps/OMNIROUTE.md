# OmniRoute Deployment

[OmniRoute](https://github.com/diegosouzapw/OmniRoute) is an AI gateway that aggregates 376+ providers (OpenAI, Anthropic, Groq, DeepSeek, etc.) behind one endpoint with automatic fallback, token compression (15-95% savings), and AES-256-GCM encrypted credential storage.

## Architecture

```text
Client (Claude Code, Codex, Cursor, etc.)
    |
    v
Traefik (omniroute.charana.dev, private zone - Tailscale only)
    |
    v
OmniRoute Service (ClusterIP :80 -> :20128)
    |
    v
OmniRoute Pod (diegosouzapw/omniroute:latest)
    - Node.js app with dashboard + /v1 API
    - SQLite database (encrypted with AES-256-GCM)
    - 8Gi heap for coding agents
    - PVC: 5Gi for data/logs
```

## Prerequisites

- k3s cluster with Traefik + cert-manager
- Tailscale access (private zone enforcement)
- `apps` namespace

## Setup

### 1. Generate and Create Encryption Secret

**CRITICAL**: The encryption key secures all provider credentials (API keys, OAuth tokens). Back it up securely.

```bash
# Run the secret generator script
./scripts/create-omniroute-secrets.sh

# The script will:
# 1. Generate a 256-bit AES key with openssl
# 2. Display the key (SAVE IT in a password manager!)
# 3. Create the omniroute-encryption secret in apps namespace
```

**Manual method** (if you prefer):

```bash
# Generate encryption key
ENCRYPTION_KEY=$(openssl rand -hex 32)
echo "Save this key: $ENCRYPTION_KEY"

# Create secret
kubectl create secret generic omniroute-encryption \
  -n apps \
  --from-literal=storage-encryption-key="$ENCRYPTION_KEY"
```

### 2. Deploy OmniRoute

```bash
# Apply the manifests
kubectl apply -f manifests/99-apps/omniroute.yaml

# Check deployment status
kubectl get pods -n apps -l app=omniroute
kubectl logs -n apps -l app=omniroute -f

# Verify ingress
kubectl get ingress -n apps omniroute
```

### 3. Access Dashboard

- **URL**: `https://omniroute.charana.dev`
- **Access**: Tailscale-connected clients only (private zone)
- **First time**: Setup wizard walks through provider configuration

### 4. Add Providers

Dashboard → **Providers** → Select a provider:

#### Option A: Free Tier Providers (no credit card)

- **SiliconFlow** - DeepSeek V3.2/R1, free tier
- **Groq** - Fast inference, free tier with rate limits
- **Kilo Code** - Auto-router + Tencent Hy3, free forever
- **OpenCode Zen** - DeepSeek V4, no token cap
- **Requesty** - GPT-OSS 120B, free forever

#### Option B: Paid Providers (API key)

- **OpenAI** - GPT-4/GPT-5, requires API key
- **Anthropic** - Claude Opus/Sonnet, requires API key
- **Groq** - Fast inference with paid tier
- **xAI** - Grok models

#### Option C: OAuth Providers (browser login)

- **Codex** - OAuth with Codex account
- **Grok Build** - OAuth with xAI account
- **Gemini Web** - Cookie-based (Playwright)

### 5. Configure Your Coding Tool

Point your IDE/CLI to OmniRoute:

```bash
# Get your OmniRoute API key from Dashboard → Endpoints
BASE_URL=https://omniroute.charana.dev/v1
API_KEY=<copy-from-dashboard>
MODEL=auto  # or specific provider/model
```

**Claude Code** (`~/.anthropic/claudecode/config.json`):

```json
{
  "apiConfiguration": {
    "baseUrl": "https://omniroute.charana.dev/v1",
    "apiKey": "YOUR_OMNIROUTE_KEY"
  }
}
```

**Cursor** (`~/.cursor/config.json`):

```json
{
  "apiKey": "YOUR_OMNIROUTE_KEY",
  "baseUrl": "https://omniroute.charana.dev/v1"
}
```

**OpenAI SDK**:

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://omniroute.charana.dev/v1",
    api_key="YOUR_OMNIROUTE_KEY"
)

response = client.chat.completions.create(
    model="auto",  # or "openai/gpt-4", "anthropic/claude-opus-5", etc.
    messages=[{"role": "user", "content": "Hello!"}]
)
```

## Files

| File | Description |
|------|-------------|
| `manifests/99-apps/omniroute.yaml` | Deployment, Service, PVC, Ingress |
| `manifests/99-apps/omniroute-secrets-template.yaml` | Secret template (DO NOT COMMIT with real values) |
| `scripts/create-omniroute-secrets.sh` | Encryption key generator |
| `docs/apps/OMNIROUTE.md` | This file |

## Storage & Encryption

- **Database**: SQLite at `/app/data/storage.sqlite` (5Gi PVC)
- **Encryption**: AES-256-GCM with scrypt key derivation
- **Encrypted fields**: API keys, OAuth tokens, refresh tokens, proxy credentials
- **Encryption key**: Required via `STORAGE_ENCRYPTION_KEY` env var (from `omniroute-encryption` secret)

### What Happens if I Lose the Encryption Key?

**No recovery possible.** All encrypted credentials become unreadable. You must:

1. Delete the existing secret
2. Generate a new encryption key
3. Re-add all providers manually in the dashboard

**Mitigation**: Always back up the encryption key in:
- Password manager (1Password, Bitwarden, etc.)
- KMS (AWS Secrets Manager, Google Secret Manager, HashiCorp Vault)
- Encrypted offline backup (NOT in Git)

## Backup & Restore

### Backup

```bash
# 1. Backup encryption key (DO THIS FIRST!)
kubectl get secret omniroute-encryption -n apps -o yaml > omniroute-encryption-backup.yaml
# Store this file securely (NOT in Git)

# 2. Backup SQLite database
kubectl exec -n apps deployment/omniroute -- \
  sqlite3 /app/data/storage.sqlite ".backup /app/data/backup.sqlite"

kubectl cp apps/$(kubectl get pod -n apps -l app=omniroute -o jsonpath='{.items[0].metadata.name}'):/app/data/backup.sqlite \
  ./omniroute-backup-$(date +%Y%m%d).sqlite
```

### Restore

```bash
# 1. Restore encryption key (REQUIRED, or the backup is useless)
kubectl apply -f omniroute-encryption-backup.yaml

# 2. Restore database
kubectl cp ./omniroute-backup-YYYYMMDD.sqlite \
  apps/$(kubectl get pod -n apps -l app=omniroute -o jsonpath='{.items[0].metadata.name}'):/app/data/storage.sqlite

# 3. Restart pod
kubectl rollout restart deployment/omniroute -n apps
```

## Monitoring

```bash
# Logs
kubectl logs -n apps -l app=omniroute -f

# Pod status
kubectl get pods -n apps -l app=omniroute

# Resource usage
kubectl top pod -n apps -l app=omniroute

# Health endpoint
curl -k https://omniroute.charana.dev/api/health
```

## Troubleshooting

### Pod won't start - encryption key error

```
Error: STORAGE_ENCRYPTION_KEY is not set
```

**Fix**: Ensure the `omniroute-encryption` secret exists:

```bash
kubectl get secret omniroute-encryption -n apps
# If missing, run: ./scripts/create-omniroute-secrets.sh
```

### Out of memory (OOMKilled)

Coding agents (Claude Code, Codex, Grok Build) need more memory for long contexts.

**Fix**: Increase memory in `manifests/99-apps/omniroute.yaml`:

```yaml
env:
- name: OMNIROUTE_MEMORY_MB
  value: "10240"  # 10Gi heap

resources:
  limits:
    memory: "12Gi"  # Must be > heap for native buffers
```

Then apply:

```bash
kubectl apply -f manifests/99-apps/omniroute.yaml
kubectl rollout restart deployment/omniroute -n apps
```

### Can't access dashboard (403 Forbidden)

OmniRoute is in the **private zone** (Tailscale only).

**Fix**: Connect to Tailscale, then access `https://omniroute.charana.dev`

### Provider credentials not saving

Check if encryption key is correctly set:

```bash
# Check secret exists
kubectl get secret omniroute-encryption -n apps -o yaml

# Check pod env
kubectl exec -n apps deployment/omniroute -- env | grep STORAGE_ENCRYPTION_KEY
```

## Upgrading

```bash
# 1. Backup first (see Backup section above)

# 2. Update image tag in manifests/99-apps/omniroute.yaml
# image: diegosouzapw/omniroute:v3.8.54  # or :latest

# 3. Apply changes
kubectl apply -f manifests/99-apps/omniroute.yaml

# 4. Check rollout
kubectl rollout status deployment/omniroute -n apps
kubectl logs -n apps -l app=omniroute -f
```

## Uninstall

```bash
# 1. BACKUP encryption key first! (see Backup section)

# 2. Delete resources
kubectl delete -f manifests/99-apps/omniroute.yaml

# 3. Optionally delete PVC (this deletes all data)
kubectl delete pvc omniroute-data -n apps

# 4. Optionally delete secret
kubectl delete secret omniroute-encryption -n apps
```

## Resources

- **Official Docs**: https://omniroute.online
- **GitHub**: https://github.com/diegosouzapw/OmniRoute
- **Docker Hub**: https://hub.docker.com/r/diegosouzapw/omniroute
- **Discord**: https://discord.gg/U47eFqAXCn
