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
│   ├── 03-monitoring/  # Beszel, Kubernetes Dashboard, Headlamp
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

## Kubernetes Web UI (Headlamp)

[Headlamp](https://headlamp.dev) is an actively maintained Kubernetes web UI, replacing the unmaintained Kubernetes Dashboard. It runs in the `monitoring` namespace behind Traefik at `https://headlamp.charana.dev`. Authentication uses a ServiceAccount bearer token; the backend reaches the API via its own in-cluster service account.

### Setup

```bash
# 1. Label the always-on control-plane node for monitoring workloads
#    (only needed once; already done if Beszel is deployed)
kubectl label node <oracle-node> workload=monitoring

# 2. Apply RBAC (ServiceAccount + cluster-admin binding + token Secret)
kubectl apply -f manifests/03-monitoring/headlamp-rbac.yaml

# 3. Apply the Deployment, Service, IngressRoute, and TLS certificate
kubectl apply -f manifests/03-monitoring/headlamp.yaml

# 4. Retrieve the login token
./scripts/create-headlamp-token.sh

# 5. Visit https://headlamp.charana.dev, choose "Bearer token", paste the token
```

### Files

| File | Description |
|------|-------------|
| `manifests/03-monitoring/headlamp.yaml` | Deployment, Service, Middleware, Certificate, IngressRoutes (headlamp.charana.dev) |
| `manifests/03-monitoring/headlamp-rbac.yaml` | `headlamp-admin` ServiceAccount + cluster-admin ClusterRoleBinding + token Secret |
| `scripts/create-headlamp-token.sh` | Prints/mints a ServiceAccount token for logging in to Headlamp |

> The old Kubernetes Dashboard files are retained side-by-side during the transition. Metrics (CPU/memory) charts work out-of-the-box since k3s ships metrics-server; no metrics-scraper sidecar is needed (unlike the old dashboard).

## Network Zones (Private / Public)

Cluster services are split into two access zones behind Traefik. URLs stay the same for everyone; the only difference is whether the client is connected to Tailscale.

| Zone | Reachable from | Mechanism |
|------|----------------|-----------|
| **public** | Anyone on the internet | No access-control middleware |
| **private** | Tailscale-connected clients only | `private-zone-only` middleware (Traefik `ipAllowList`) |

Non-Tailscale clients hitting a private service get a **403 Forbidden** from Traefik.

### Zone assignment

| Host | Zone |
|------|------|
| `charana.dev`, `www.charana.dev` (portfolio) | public |
| `media.charana.dev` (jellyfin) | public |
| `cloud.charana.dev` (nextcloud) | private |
| `office.charana.dev` (collabora) | private |
| `photos.charana.dev` (immich) | private |
| `radarr` / `prowlarr` / `torrent` / `sonarr` / `lidarr` `.charana.dev` | private |
| `llm.charana.dev` (open-webui) | private |
| `ai.charana.dev` (hermes) | private |
| `beszel.charana.dev` | private |
| `headlamp.charana.dev` | private |
| `k8s.charana.dev` (kubernetes dashboard) | private |

### How it works

The shared middleware `private-zone-only` lives in `kube-system` (`manifests/01-networking/private-zone.yaml`) and allows only the Tailscale CGNAT ranges (`100.64.0.0/10`, `fd7a:115c:a1::/48`). It is attached to each private Ingress / IngressRoute. Public ingresses have no such middleware.

Let's Encrypt cert issuance/renewal is unaffected: cert-manager's HTTP-01 solver creates its own challenge Ingress that is not gated by the per-app middleware.

### Source IP preservation (REQUIRED for ipAllowList to work)

The `ipAllowList` middleware only sees the Tailscale `100.x` source IP if Traefik receives the **real** client address. By default, Kubernetes SNATs the source IP before traffic reaches Traefik, so Traefik sees an internal node IP — not the client IP.

The fix is `manifests/01-networking/traefik-helm-config.yaml` — a k3s `HelmChartConfig` that sets `externalTrafficPolicy: Local` on the Traefik Service. This tells Kubernetes to preserve the original source IP end-to-end (no SNAT). Traefik is pinned to `charana-vps` via `nodeSelector` because `Local` only forwards to Traefik pods on the same node where traffic arrives.

### Split-DNS (REQUIRED for Tailscale clients to reach private services)

Public DNS resolves `*.charana.dev` to the Oracle node's **public** IP (`80.225.224.42`). On a cloud VM with 1:1 NAT, Tailscale-on clients reaching the public IP arrive at Traefik with their **ISP IP** (not a Tailscale `100.x` address), so the ipAllowList rejects them (403) — even with `externalTrafficPolicy: Local` preserving the real source.

The fix is split-DNS: an in-cluster CoreDNS (`manifests/01-networking/split-dns.yaml`) resolves private `*.charana.dev` subdomains to the Oracle node's **Tailscale IP** (`100.126.165.111`) instead of the public IP. Traffic stays inside the Tailscale tunnel and arrives at Traefik with a `100.x` source → ipAllowList passes → 200. Public subdomains (`charana.dev`, `www.charana.dev`, `media.charana.dev`) still resolve to the public IP.

| Client | DNS resolves private services to | Source Traefik sees | Result |
|--------|-----------------------------------|--------------------|--------|
| Tailscale ON | `100.126.165.111` (Tailscale IP) | `100.x` | 200 |
| Tailscale OFF | `80.225.224.42` (public IP) | ISP IP | 403 |

### Setup

```bash
# 1. Remove any previous Traefik HelmChartConfig (e.g. hostNetwork)
kubectl delete helmchartconfig traefik -n kube-system 2>/dev/null || true

# 2. Apply the shared middleware + Traefik source-IP config + split-DNS
kubectl apply -f manifests/01-networking/private-zone.yaml
kubectl apply -f manifests/01-networking/traefik-helm-config.yaml
kubectl apply -f manifests/01-networking/split-dns.yaml

# 3. Wait for Traefik to restart
kubectl rollout status deployment/traefik -n kube-system

# 4. Apply the updated ingresses + namespace labels
./scripts/apply-manifests.sh

# 5. Verify CoreDNS is serving the right records
dig @100.126.165.111 photos.charana.dev   # -> 100.126.165.111
dig @100.126.165.111 charana.dev          # -> 80.225.224.42

# 6. Verify Traefik config
kubectl get svc -n kube-system traefik \
  -o jsonpath='{.spec.externalTrafficPolicy}{"\n"}'   # Local
```

### Tailscale-side setup (REQUIRED, out-of-cluster)

```bash
# 1. On the Oracle node, remove any previous advertise-route
sudo tailscale up    # drop --advertise-routes if previously set

# 2. In the Tailscale admin console, configure split-DNS:
#    https://login.tailscale.com/admin/dns
#    Nameservers -> Add nameserver -> Custom
#    IP: 100.126.165.111   Restrict to domain: charana.dev
#    Save

# 3. On clients, remove --accept-routes (no longer needed)
tailscale up    # drop --accept-routes
```

### Verify

```bash
# CoreDNS is serving the right records
dig @100.126.165.111 photos.charana.dev   # -> 100.126.165.111
dig @100.126.165.111 charana.dev          # -> 80.225.224.42

# Tailscale OFF -> private service returns 403, public returns 200
curl -I https://photos.charana.dev    # 403
curl -I https://charana.dev          # 200

# Tailscale ON -> both return 200
curl -I https://photos.charana.dev    # 200
curl -I https://charana.dev           # 200
```

## Security Notes

- Never commit secrets to this repo
- Use Kubernetes Secrets or external secret management
- Keep `secrets/` directory in `.gitignore`

## Contributing

1. Create feature branch
2. Test changes with `kubectl apply --dry-run=client`
3. Submit PR with description of changes
