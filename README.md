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
│   ├── 03-monitoring/  # Prometheus, Grafana (optional)
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

## Security Notes

- Never commit secrets to this repo
- Use Kubernetes Secrets or external secret management
- Keep `secrets/` directory in `.gitignore`

## Contributing

1. Create feature branch
2. Test changes with `kubectl apply --dry-run=client`
3. Submit PR with description of changes
