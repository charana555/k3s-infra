#!/bin/bash
set -euo pipefail

# =============================================================================
# Manual Backup Trigger Script
# =============================================================================
# Triggers backup Jobs on the Fedora backup node
#
# Usage:
#   ./trigger-backup.sh etcd        # Trigger etcd snapshot backup
#   ./trigger-backup.sh pv          # Trigger PV data backup with restic
#   ./trigger-backup.sh all         # Trigger both backups
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

show_help() {
    cat << EOF
Manual Backup Trigger

Usage:
  $0 <etcd|pv|all>

Commands:
  etcd    Trigger etcd snapshot backup
  pv      Trigger PersistentVolume data backup (restic)
  all     Trigger both backups

Examples:
  $0 etcd     # Backup cluster state
  $0 pv       # Backup all PV data
  $0 all      # Full backup

Note: Ensure the Fedora backup node is online before running.
EOF
    exit 0
}

trigger_etcd_backup() {
    log_info "Triggering etcd snapshot backup..."
    
    # Check if backup node is online
    if ! kubectl get nodes -l workload=backup -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        log_error "Backup node is not online or not ready"
        log_info "Turn on your Fedora laptop and ensure it's joined to the cluster"
        return 1
    fi
    
    # Create unique job name with timestamp
    JOB_NAME="etcd-backup-manual-$(date +%s)"
    
    # Create job from template
    # Note: Using <<EOF with escaped container variables (\$) so they execute inside the pod
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: backup
spec:
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      nodeSelector:
        workload: backup
      tolerations:
      - key: dedicated
        operator: Equal
        value: backup
        effect: NoSchedule
      containers:
      - name: etcd-backup
        image: rancher/k3s:v1.30.5-k3s1
        command:
        - /bin/sh
        - -c
        - |
          TIMESTAMP=\$(date +%Y%m%d-%H%M%S)
          k3s etcd-snapshot save --etcd-snapshot-dir=/backup/etcd --name=\${TIMESTAMP}
          echo "Backup completed: \${TIMESTAMP}"
          echo "Available snapshots:"
          ls -lah /backup/etcd/
        volumeMounts:
        - name: backup-storage
          mountPath: /backup
        - name: k3s-server
          mountPath: /var/lib/rancher/k3s/server
          readOnly: true
      volumes:
      - name: backup-storage
        hostPath:
          path: /mnt/backup
          type: DirectoryOrCreate
      - name: k3s-server
        hostPath:
          path: /var/lib/rancher/k3s/server
          type: Directory
      restartPolicy: OnFailure
EOF
    
    log_success "Etcd backup job created: ${JOB_NAME}"
    log_info "Monitor with: kubectl logs -f job/${JOB_NAME} -n backup"
    
    # Wait for completion
    log_info "Waiting for backup to complete..."
    kubectl wait --for=condition=complete --timeout=300s job/${JOB_NAME} -n backup || {
        log_warn "Backup timed out or failed. Check logs:"
        echo "  kubectl logs job/${JOB_NAME} -n backup"
        return 1
    }
    
    log_success "Etcd backup completed successfully!"
}

trigger_pv_backup() {
    log_info "Triggering PV data backup..."
    
    # Check if backup node is online
    if ! kubectl get nodes -l workload=backup -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        log_error "Backup node is not online or not ready"
        log_info "Turn on your Fedora laptop and ensure it's joined to the cluster"
        return 1
    fi
    
    # Check if restic secret exists
    if ! kubectl get secret restic-password -n backup &>/dev/null; then
        log_error "Restic password secret not found"
        log_info "Create it with:"
        echo "  kubectl create secret generic restic-password \\"
        echo "    --from-literal=password=YOUR_STRONG_PASSWORD \\"
        echo "    -n backup"
        return 1
    fi
    
    # Create unique job name with timestamp
    JOB_NAME="pv-backup-manual-$(date +%s)"
    
    # Create job from template
    # Note: Using <<EOF with escaped container variables (\$) so they execute inside the pod
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: backup
spec:
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      nodeSelector:
        workload: backup
      tolerations:
      - key: dedicated
        operator: Equal
        value: backup
        effect: NoSchedule
      containers:
      - name: restic-backup
        image: restic/restic:0.16.4
        command:
        - /bin/sh
        - -c
        - |
          # Initialize repository if needed
          if ! restic -r /backup/restic snapshots > /dev/null 2>&1; then
            echo "Initializing restic repository..."
            restic -r /backup/restic init
          fi
          
          # Create backup
          TIMESTAMP=\$(date +%Y%m%d)
          echo "Starting backup at \$(date)"
          restic -r /backup/restic backup \
            --tag \${TIMESTAMP} \
            --exclude-if-present .nobackup \
            /data
          
          echo "Pruning old snapshots..."
          restic -r /backup/restic forget \
            --keep-daily 30 \
            --keep-weekly 12 \
            --keep-monthly 12 \
            --prune
          
          echo "Backup completed successfully"
          echo ""
          echo "Snapshot list:"
          restic -r /backup/restic snapshots
        env:
        - name: RESTIC_PASSWORD
          valueFrom:
            secretKeyRef:
              name: restic-password
              key: password
        volumeMounts:
        - name: backup-storage
          mountPath: /backup
        - name: pv-data
          mountPath: /data
      volumes:
      - name: backup-storage
        hostPath:
          path: /mnt/backup
          type: DirectoryOrCreate
      - name: pv-data
        hostPath:
          path: /var/lib/rancher/k3s/storage
          type: DirectoryOrCreate
      restartPolicy: OnFailure
EOF
    
    log_success "PV backup job created: ${JOB_NAME}"
    log_info "Monitor with: kubectl logs -f job/${JOB_NAME} -n backup"
    
    # Wait for completion
    log_info "Waiting for backup to complete..."
    kubectl wait --for=condition=complete --timeout=3600s job/${JOB_NAME} -n backup || {
        log_warn "Backup timed out or failed. Check logs:"
        echo "  kubectl logs job/${JOB_NAME} -n backup"
        return 1
    }
    
    log_success "PV backup completed successfully!"
}

# Main
case "${1:-}" in
    etcd)
        trigger_etcd_backup
        ;;
    pv)
        trigger_pv_backup
        ;;
    all)
        trigger_etcd_backup
        echo ""
        trigger_pv_backup
        ;;
    -h|--help|help)
        show_help
        ;;
    *)
        log_error "Unknown command: ${1:-}"
        show_help
        exit 1
        ;;
esac
