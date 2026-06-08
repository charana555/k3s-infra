# K3s Cluster Expansion Plan

## Current State

**Cluster:** k3s on 2x Oracle Always Free instances (4 vCPU, 24GB RAM, 200GB each)  
**Apps:** Portfolio, Dashboard, Collabora, Open WebUI → Ollama  
**Ingress:** Traefik with Let's Encrypt  
**Storage:** local-path (default)  
**Network:** Oracle cloud networking (public IPs)

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│           TAILSCALE MESH VPN                │
│                                             │
│  ┌──────────────┐  ┌──────────────┐        │
│  │ Oracle Node 1│  │ Oracle Node 2│        │
│  │ (Control)    │  │ (Worker)     │        │
│  │ 4vCPU/24GB   │  │ 4vCPU/24GB   │        │
│  │ Always Online│  │ Always Online│        │
│  └──────────────┘  └──────────────┘        │
│                                             │
│  ┌──────────────┐  ┌──────────────┐        │
│  │ Fedora Laptop│  │ Pop!_OS      │        │
│  │ 1TB Storage  │  │ RTX 3060 6GB │        │
│  │ Backup Node  │  │ LLM Node     │        │
│  │ Plug & Play  │  │ Plug & Play  │        │
│  └──────────────┘  └──────────────┘        │
└─────────────────────────────────────────────┘
```

---

## Phase 1: Tailscale Mesh Network Setup

### On ALL Nodes (Oracle + Laptops)

1. Install Tailscale:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up --advertise-routes=10.42.0.0/16,10.43.0.0/16
   ```

2. Enable IP forwarding on Oracle nodes (for pod subnet routing):
   ```bash
   echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
   sudo sysctl -p
   ```

3. Approve subnet routes in Tailscale admin console

4. Disable key expiry for server nodes in Tailscale console

### Firewall Rules

Tailscale handles NAT traversal, but ensure these ports are open **within** the Tailscale network:
- `6443/tcp` - Kubernetes API server
- `10250/tcp` - Kubelet
- `2379/tcp` - etcd client
- `2380/tcp` - etcd peer
- `8472/udp` - Flannel VXLAN (pod networking)

---

## Phase 2: Fedora Laptop (Backup Node)

### Hardware Specs
- **Role:** Dedicated backup node
- **Storage:** 1TB local drive
- **Connectivity:** Plug & play via Tailscale

### Node Configuration

#### 1. OS Prep
```bash
# Mount 1TB drive (adjust device path as needed)
sudo mkdir -p /mnt/backup
sudo blkid  # Find UUID of your 1TB drive
echo 'UUID=<your-uuid> /mnt/backup ext4 defaults,noatime 0 2' | sudo tee -a /etc/fstab
sudo mount -a

# Install required packages
sudo dnf install -y restic
```

#### 2. Join k3s as Agent
```bash
# Get token from control plane
ssh ubuntu@<oracle-node-tailscale-ip> "sudo cat /var/lib/rancher/k3s/server/node-token"

# Join cluster
curl -sfL https://get.k3s.io | \
  K3S_URL=https://<oracle-control-plane-tailscale-ip>:6443 \
  K3S_TOKEN=<token> \
  K3S_NODE_NAME=fedora-backup \
  sh -

# Label and taint the node
kubectl label node fedora-backup workload=backup storage=local-1tb
kubectl taint node fedora-backup dedicated=backup:NoSchedule
```

#### 3. Node Labels & Taints

| Label | Value |
|-------|-------|
| `workload` | `backup` |
| `storage` | `local-1tb` |

| Taint | Effect |
|-------|--------|
| `dedicated=backup` | `NoSchedule` |

---

## Phase 3: Pop!_OS Laptop (LLM Node)

### Hardware Specs
- **Role:** GPU-accelerated LLM inference
- **GPU:** NVIDIA RTX 3060 6GB
- **Connectivity:** Plug & play via Tailscale

### Node Configuration

#### 1. NVIDIA Drivers & CUDA
```bash
# Pop!_OS usually has NVIDIA drivers preinstalled
# Verify GPU:
nvidia-smi

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=containerd
sudo systemctl restart containerd
```

#### 2. Join k3s as Agent
```bash
# Join cluster
curl -sfL https://get.k3s.io | \
  K3S_URL=https://<oracle-control-plane-tailscale-ip>:6443 \
  K3S_TOKEN=<token> \
  K3S_NODE_NAME=popos-llm \
  sh -

# Label node
kubectl label node popos-llm nvidia.com/gpu.present=true workload=llm accelerator=nvidia-gtx-3060

# Taint is already expected by Ollama deployment
kubectl taint node popos-llm dedicated=llm:NoSchedule
```

#### 3. NVIDIA Device Plugin
```bash
# Deploy NVIDIA device plugin to enable GPU scheduling
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
```

#### 4. Node Labels & Taints

| Label | Value |
|-------|-------|
| `nvidia.com/gpu.present` | `true` |
| `workload` | `llm` |
| `accelerator` | `nvidia-gtx-3060` |

| Taint | Effect |
|-------|--------|
| `dedicated=llm` | `NoSchedule` |

---

## Phase 4: Backup Strategy

### What Gets Backed Up

1. **etcd Snapshots** - Full cluster state
2. **PersistentVolume Data** - Using restic to backup mounted PVCs

Both backups are triggered manually via `./scripts/trigger-backup.sh`.

### Backup Jobs (Manual)

#### etcd Snapshot Backup
Triggered with: `./scripts/trigger-backup.sh etcd`

This creates a Job that:
- Runs on the Fedora backup node
- Creates a timestamped etcd snapshot
- Saves to `/mnt/backup/etcd/` on the Fedora node's 1TB drive

#### PV Data Backup with Restic
Triggered with: `./scripts/trigger-backup.sh pv`

This creates a Job that:
- Runs on the Fedora backup node
- Backs up all PVC data from `/var/lib/rancher/k3s/storage/`
- Uses restic with automatic repository initialization
- Prunes old snapshots (retains 30 daily, 12 weekly, 12 monthly)
- Saves encrypted snapshots to `/mnt/backup/restic/` on the Fedora node

### Trigger Script

A helper script is provided at `scripts/trigger-backup.sh`:

```bash
# etcd snapshot only
./scripts/trigger-backup.sh etcd

# PV data only
./scripts/trigger-backup.sh pv

# Both
./scripts/trigger-backup.sh all
```

Each run creates a unique Job with a timestamp. Jobs auto-delete after 24 hours.

### Backup Retention Policy
- **etcd snapshots:** Manual management (stored in `/mnt/backup/etcd/`)
- **restic backups:** 
  - Daily snapshots kept for 30 days
  - Weekly snapshots kept for 12 weeks
  - Monthly snapshots kept for 12 months

---

## Phase 5: LLM Workload Scheduling

### Current State (No Changes Needed)

Your `ollama.yaml` is already correctly configured:
```yaml
nodeSelector:
  workload: llm
tolerations:
- key: dedicated
  operator: Equal
  value: llm
  effect: NoSchedule
```

This means:
- ✅ Ollama **only** runs on `popos-llm` node
- ✅ When Pop!_OS laptop is offline, Ollama stays in `Pending`
- ✅ No accidental scheduling on Oracle nodes

### Open WebUI Fallback Configuration

Update `open-webui.yaml` to support OpenRouter API fallback when Ollama is unavailable:

```yaml
# Add to open-webui container env:
env:
- name: OLLAMA_BASE_URL
  value: "http://ollama.llm.svc.cluster.local:11434"
- name: OPENAI_API_BASE_URL  # OpenRouter compatible
  value: "https://openrouter.ai/api/v1"
- name: OPENAI_API_KEY
  valueFrom:
    secretKeyRef:
      name: openrouter-api-key
      key: api-key
```

Open WebUI will:
1. Try Ollama first (local GPU inference)
2. Automatically fall back to OpenRouter when Ollama is unreachable

---

## Phase 6: Required Manifest Changes

### New Files to Create

```
k3s-infra/
├── manifests/
│   ├── 00-namespace/
│   │   └── namespace.yaml          ← ADD: backup namespace
│   ├── 01-networking/
│   │   └── cluster-issuer.yaml     ← NO CHANGE
│   ├── 02-storage/
│   │   └── storage-class.yaml      ← NO CHANGE
│   ├── 03-monitoring/
│   │   └── ...                     ← NO CHANGE
│   ├── 04-nas/
│   │   └── ...                     ← NO CHANGE
│   ├── 05-llm/
│   │   └── ollama.yaml             ← NO CHANGE (already configured)
│   ├── 06-backup/                   ← NEW DIRECTORY
│   │   ├── etcd-backup-job.yaml    ← Job template (or use trigger script)
│   │   ├── pv-backup-job.yaml      ← Job template (or use trigger script)
│   │   └── restic-secret-template.yaml
│   └── 99-apps/
│       ├── open-webui.yaml         ← UPDATE: Add OpenRouter fallback
│       └── ...                     ← NO CHANGE
└── scripts/
    ├── join-fedora.sh              ← NEW
    └── join-popos.sh               ← NEW
```

### Modified Files

#### `manifests/00-namespace/namespace.yaml`
Add:
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: backup
  labels:
    environment: system
    managed-by: k3s-infra
```

#### `manifests/99-apps/open-webui.yaml`
Add environment variables for OpenRouter fallback (shown above)

---

## Phase 7: Node Join Scripts

### `scripts/join-fedora.sh`
```bash
#!/bin/bash
set -e

K3S_URL="https://<oracle-tailscale-ip>:6443"
NODE_NAME="fedora-backup"

echo "Joining k3s cluster as backup node..."
read -p "Enter k3s token: " TOKEN

curl -sfL https://get.k3s.io | \
  K3S_URL=$K3S_URL \
  K3S_TOKEN=$TOKEN \
  K3S_NODE_NAME=$NODE_NAME \
  sh -

echo "Node joined. Run on control plane:"
echo "  kubectl label node $NODE_NAME workload=backup storage=local-1tb"
echo "  kubectl taint node $NODE_NAME dedicated=backup:NoSchedule"
```

### `scripts/join-popos.sh`
```bash
#!/bin/bash
set -e

K3S_URL="https://<oracle-tailscale-ip>:6443"
NODE_NAME="popos-llm"

echo "Joining k3s cluster as LLM node..."
echo "Make sure NVIDIA drivers and container toolkit are installed!"
read -p "Enter k3s token: " TOKEN

curl -sfL https://get.k3s.io | \
  K3S_URL=$K3S_URL \
  K3S_TOKEN=$TOKEN \
  K3S_NODE_NAME=$NODE_NAME \
  sh -

echo "Node joined. Run on control plane:"
echo "  kubectl label node $NODE_NAME nvidia.com/gpu.present=true workload=llm"
echo "  kubectl taint node $NODE_NAME dedicated=llm:NoSchedule"
echo "  kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml"
```

---

## Operational Behavior

### When Pop!_OS is OFFLINE
- ❌ Ollama pod: `Pending` (waiting for GPU node)
- ✅ Open WebUI: Still runs on Oracle nodes, falls back to OpenRouter API
- ✅ All other services: Unaffected

### When Pop!_OS is ONLINE
- ✅ Ollama pod: Scheduled on `popos-llm`, GPU acceleration active
- ✅ Open WebUI: Uses local Ollama for fast inference
- ✅ All other services: Unaffected

### When Fedora is OFFLINE
- ❌ Backup jobs: Will queue but can't execute (expected)
- ✅ No impact on running services
- ✅ When Fedora comes back online, queued jobs will run

### When Fedora is ONLINE
- ✅ etcd snapshots: Every 6 hours
- ✅ PV backups: Daily at 2 AM
- ✅ Manual backups: Available via script/trigger

---

## Security Considerations

1. **Tailscale ACLs:** Restrict who can join your tailnet
2. **Node Taints:** Prevent unauthorized workloads on special-purpose nodes
3. **Restic encryption:** Password-protected backup repository
4. **API Keys:** Store OpenRouter key in Kubernetes Secrets (never in Git)
5. **Token Rotation:** Rotate k3s join token periodically

---

## Implementation Order

1. ✅ **Install Tailscale** on all 4 nodes
2. ✅ **Configure** Oracle nodes to advertise pod subnets
3. ✅ **Test** Tailscale connectivity between all nodes
4. ✅ **Join Fedora** node to cluster
5. ✅ **Join Pop!_OS** node to cluster + install GPU plugin
6. ✅ **Apply** backup manifests (manual Jobs, no CronJobs)
7. ✅ **Update** Open WebUI with OpenRouter fallback
8. ✅ **Test** backup execution via `./scripts/trigger-backup.sh`
9. ✅ **Test** LLM scheduling and fallback

---

## Open Questions / Decisions

1. **Should we set up automatic OpenRouter API key rotation?**
2. **Any specific PVCs that should be excluded from backup (e.g., cache volumes)?**

Would you like me to proceed with implementing this plan?