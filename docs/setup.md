# K3s Setup Guide

## Initial Server Setup

### 1. Install k3s

```bash
# Standard install (single node)
curl -sfL https://get.k3s.io | sh -

# Verify installation
sudo systemctl status k3s
sudo k3s kubectl get nodes
```

### 2. Configure kubectl Access

```bash
# Create kubeconfig directory
mkdir -p ~/.kube

# Copy k3s config
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config

# Add to shell profile
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
source ~/.bashrc
```

### 3. Clone This Repository

```bash
git clone <your-repo-url>
cd k3s-infra
```

### 4. Apply Manifests

```bash
# Apply everything in order
./scripts/apply-manifests.sh

# Or apply specific directories
kubectl apply -f manifests/00-namespace/
kubectl apply -f manifests/99-apps/
```

## Multi-Node Setup (Optional)

### Add Worker Nodes

On control plane node:
```bash
# Get join token
sudo cat /var/lib/rancher/k3s/server/node-token
```

On worker node:
```bash
# Install k3s agent
curl -sfL https://get.k3s.io | K3S_URL=https://<control-plane-ip>:6443 K3S_TOKEN=<token> sh -
```

## Configuration

### Custom k3s Config

Create `/etc/rancher/k3s/config.yaml`:
```yaml
tls-san:
  - k3s.yourdomain.com
node-label:
  - "region=us-west"
  - "zone=a"
```

### Traefik Customization

Edit `config/traefik-values.yaml` for custom ingress settings.

## Verification

```bash
# Check cluster status
./scripts/check-status.sh

# Test with sample app
kubectl apply -f manifests/99-apps/sample-deployment.yaml

# Access sample app
kubectl port-forward svc/sample-app 8080:80 -n production
# Visit http://localhost:8080
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   sudo chmod 644 /etc/rancher/k3s/k3s.yaml
   ```

2. **Pod stuck in Pending**
   ```bash
   kubectl describe pod <pod-name>
   kubectl get events --field-selector reason=FailedScheduling
   ```

3. **Service Unreachable**
   ```bash
   kubectl get svc -n <namespace>
   kubectl get endpoints -n <namespace>
   ```

## Next Steps

- [ ] Configure Traefik for external access
- [ ] Set up SSL/TLS certificates
- [ ] Deploy your applications
- [ ] Configure monitoring (Prometheus/Grafana)
- [ ] Set up backups
