# Archived Manifests

Archived on: 2026-11-12

## Reason
Unused services identified for removal

## Contents

### Monitoring Stack
- Prometheus (helm)
- Loki (helm)
- Alloy (helm)
- Grafana admin secrets
- deploy-observability.sh (helm releases uninstalled from cluster 2026-11-21; Beszel + Headlamp kept)

### Backup
- etcd backup CronJob
- PV backup CronJob (Restic)

### GPU
- NVIDIA device plugin

### AI/LLM
- Ollama
- Open-WebUI
- Hermes Agent (prashan instance)
- Omniroute
- OpenClaw

### Tools
- Stirling PDF
- sample-deployment.yaml template

### Namespaces (archived 2026-11-21)
- production
- staging
- llm

## Restore
To restore any service, move manifests back and apply:
```bash
kubectl apply -f <manifest>
```
