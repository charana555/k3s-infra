#!/bin/bash
set -e

# K3s Manifest Sync Script
# Syncs local YAML manifests to remote Oracle instance

REMOTE_HOST="80.225.224.42"
REMOTE_USER="ubuntu"
SSH_KEY="${HOME}/.ssh/ssh-key-2026-02-24.key"
REMOTE_PATH="/home/ubuntu/k3s-infra"
LOCAL_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS_DIR="${LOCAL_PATH}/manifests"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

DRY_RUN=false
FORCE=false
VERBOSE=false
SINGLE_DIR=""

show_help() {
    cat << EOF
K3s Manifest Sync Tool

Syncs YAML manifests from local repo to remote Oracle k3s instance.

Usage:
  ./sync-to-remote.sh [OPTIONS]

Options:
  -h, --help          Show this help message
  -d, --dry-run       Preview changes without syncing
  -y, --yes           Skip confirmation prompts
  -v, --verbose       Show detailed output
  --dir DIR           Sync only specific directory (e.g., manifests/99-apps/)

Examples:
  ./sync-to-remote.sh                    # Interactive sync with confirmation
  ./sync-to-remote.sh --dry-run          # Preview changes
  ./sync-to-remote.sh --yes              # Sync without prompts
  ./sync-to-remote.sh --dir manifests/99-apps/  # Sync single directory

Safety Features:
  - Validates YAML syntax before transfer
  - Shows diff of changes
  - Creates backups of modified files
  - Uses rsync for efficient transfers

EOF
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_header() {
    echo -e "\n${BOLD}${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

validate_yaml_files() {
    log_header "Validating YAML Files"
    
    local total_count=0
    local invalid_count=0
    
    while IFS= read -r file; do
        total_count=$((total_count + 1))
        
        if ! kubectl apply --dry-run=client -f "$file" > /dev/null 2>&1; then
            log_error "Invalid YAML: $(basename "$file")"
            invalid_count=$((invalid_count + 1))
        else
            if [ "$VERBOSE" = true ]; then
                log_success "Valid: $(basename "$file")"
            fi
        fi
    done < <(find "${MANIFESTS_DIR}" -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null)
    
    if [ $total_count -eq 0 ]; then
        log_warn "No YAML files found"
        return 0
    fi
    
    if [ $invalid_count -gt 0 ]; then
        log_error "Found $invalid_count invalid YAML file(s) out of $total_count"
        exit 1
    fi
    
    log_success "All $total_count YAML files are valid"
}

validate_ssh_connection() {
    log_header "Checking SSH Connection"
    
    if [ ! -f "$SSH_KEY" ]; then
        log_error "SSH key not found: $SSH_KEY"
        exit 1
    fi
    
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "${REMOTE_USER}@${REMOTE_HOST}" "echo OK" > /dev/null 2>&1; then
        log_error "Cannot connect to ${REMOTE_USER}@${REMOTE_HOST}"
        log_info "Ensure SSH key is correct and host is reachable"
        exit 1
    fi
    
    log_success "SSH connection established"
}

show_sync_preview() {
    log_header "Sync Preview"
    
    echo -e "${BOLD}Files to sync:${NC}"
    
    if [ -n "$SINGLE_DIR" ]; then
        rsync -avz --dry-run -e "ssh -i ${SSH_KEY}" \
            "${LOCAL_PATH}/${SINGLE_DIR}" \
            "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" 2>&1 | grep -E "^>f|^<f" | head -20
    else
        rsync -avz --dry-run -e "ssh -i ${SSH_KEY}" \
            --include='*/' --include='*.yaml' --include='*.yml' --include='*.sh' --include='*.md' \
            --exclude='*' \
            "${LOCAL_PATH}/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" 2>&1 | grep -E "^>f|^<f" | head -20
    fi
    
    echo ""
}

backup_remote_files() {
    log_header "Creating Remote Backup"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${REMOTE_PATH}/.backup/${timestamp}"
    
    ssh -i "$SSH_KEY" "${REMOTE_USER}@${REMOTE_HOST}" "
        if [ -d ${REMOTE_PATH}/manifests ]; then
            mkdir -p ${backup_dir}
            cp -r ${REMOTE_PATH}/manifests ${backup_dir}/ 2>/dev/null || true
            echo 'Backup created: ${backup_dir}'
        else
            echo 'No existing manifests to backup'
        fi
    "
}

perform_sync() {
    log_header "Syncing Files"
    
    if [ -n "$SINGLE_DIR" ]; then
        rsync -avz --progress -e "ssh -i ${SSH_KEY}" \
            "${LOCAL_PATH}/${SINGLE_DIR}" \
            "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"
    else
        rsync -avz --progress -e "ssh -i ${SSH_KEY}" \
            --include='*/' --include='*.yaml' --include='*.yml' --include='*.sh' --include='*.md' --include='.gitignore' \
            --exclude='.git/' --exclude='.backup/' \
            "${LOCAL_PATH}/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"
    fi
    
    log_success "Sync completed"
}

verify_sync() {
    log_header "Verifying Sync"
    
    local remote_count=$(ssh -i "$SSH_KEY" "${REMOTE_USER}@${REMOTE_HOST}" "find ${REMOTE_PATH}/manifests -type f 2>/dev/null | wc -l")
    local local_count=$(find "${LOCAL_PATH}/manifests" -type f 2>/dev/null | wc -l)
    
    log_info "Local files: $local_count"
    log_info "Remote files: $remote_count"
}

show_next_steps() {
    log_header "Next Steps"
    
    echo -e "Connect to remote:"
    echo -e "  ssh ${REMOTE_USER}@${REMOTE_HOST}\n"
    
    echo -e "Apply manifests:"
    if [ -n "$SINGLE_DIR" ]; then
        echo -e "  kubectl apply -f ${REMOTE_PATH}/${SINGLE_DIR}\n"
    else
        echo -e "  kubectl apply -f ${REMOTE_PATH}/manifests/00-namespace/"
        echo -e "  kubectl apply -f ${REMOTE_PATH}/manifests/99-apps/\n"
    fi
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                FORCE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dir)
                SINGLE_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo -e "${BOLD}${CYAN}"
    echo "========================================"
    echo "    K3s Manifest Sync Tool"
    echo "========================================"
    echo -e "${NC}\n"
    
    validate_ssh_connection
    validate_yaml_files
    show_sync_preview
    
    if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
        echo ""
        read -p "Proceed with sync? [y/N]: " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            log_info "Sync cancelled"
            exit 0
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN MODE - No changes made"
        exit 0
    fi
    
    backup_remote_files
    perform_sync
    verify_sync
    show_next_steps
    
    echo -e "\n${GREEN}${BOLD}Done!${NC}\n"
}

main "$@"
