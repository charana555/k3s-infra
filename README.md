# K3s Infrastructure Repository

Infrastructure-as-code repository for managing k3s Kubernetes cluster.

## Quick Start

```bash
# Clone and setup
git clone <repo-url>
cd k3s-infra

# Apply all manifests
./scripts/apply-manifests.sh

# Check cluster status
./scripts/check-status.sh
```

## Repository Structure

```
k3s-infra/
├── manifests/          # Kubernetes YAML manifests
│   ├── 00-namespace/   # Namespace definitions
│   ├── 01-networking/  # Traefik, Ingress resources
│   ├── 02-storage/     # Storage classes and PVCs
│   ├── 03-monitoring/  # Beszel, Kubernetes Dashboard
│   └── 99-apps/        # Application deployments
├── scripts/            # Helper scripts
├── config/             # Configuration files
└── docs/               # Documentation
```

## Prerequisites

- k3s cluster running
- kubectl configured (`~/.kube/config`)
- Access to cluster

## Common Operations

```bash
# Apply everything
./scripts/apply-manifests.sh

# Check cluster health
./scripts/check-status.sh

# Backup cluster state
./scripts/backup.sh
```

## Directory Numbering Convention

Manifests are numbered for ordered application:
- `00-*`: Namespaces (applied first)
- `01-*`: Networking (Ingress, TLS)
- `02-*`: Storage (PVs, PVCs)
- `03-*`: Monitoring/Observability
- `99-*`: Applications (applied last)

## Monitoring (Beszel)

[Beszel](https://beszel.dev) provides lightweight host-level monitoring (CPU, memory, disk, temperature, GPU, SMART) with built-in alerts and native Discord notifications. The hub runs as a Deployment in `monitoring`; agents run as a DaemonSet on every node.

### Setup

```bash
# 1. Label the always-on control-plane node for monitoring workloads
kubectl label node <oracle-node> workload=monitoring

# 2. Create secrets (admin creds + agent KEY/TOKEN)
#    First run: provide admin email/password only, leave KEY/TOKEN empty
./scripts/create-beszel-secrets.sh

# 3. Apply the hub
kubectl apply -f manifests/03-monitoring/beszel-hub.yaml

# 4. Visit https://beszel.charana.dev and log in with admin credentials

# 5. Hub UI -> Settings -> Tokens -> Create Universal Token
#    Copy the KEY and TOKEN, then re-run the script:
./scripts/create-beszel-secrets.sh

# 6. Apply the agent DaemonSet (auto-registers on every node)
kubectl apply -f manifests/03-monitoring/beszel-agent.yaml

# 7. Verify agents are online
kubectl get pods -n monitoring -l app=beszel-agent -o wide

# 8. Hub UI -> Notifications -> add Discord webhook (discord://<token>@<webhookid>)
```

### Files

| File | Description |
|------|-------------|
| `manifests/03-monitoring/beszel-hub.yaml` | Hub Deployment, Service, PVC, IngressRoute (beszel.charana.dev) |
| `manifests/03-monitoring/beszel-agent.yaml` | Agent DaemonSet (hostNetwork, tolerations for all nodes) |
| `manifests/03-monitoring/beszel-secrets-template.yaml` | Template for KEY/TOKEN/admin creds |
| `scripts/create-beszel-secrets.sh` | Creates the `beszel-secrets` Kubernetes Secret |

## Security Notes

- Never commit secrets to this repo
- Use Kubernetes Secrets or external secret management
- Keep `secrets/` directory in `.gitignore`

## Contributing

1. Create feature branch
2. Test changes with `kubectl apply --dry-run=client`
3. Submit PR with description of changes
