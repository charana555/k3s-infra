#!/bin/bash
set -euo pipefail

# Sets up rclone Google Drive mount on pavan-vps.
# Run ON the node that hosts media pods (pavan-vps).
#
# Usage:
#   ./setup-rclone-gdrive.sh             # with a browser on this machine
#   ./setup-rclone-gdrive.sh --headless  # headless: authorize on another machine

HEADLESS=false
if [ "${1:-}" = "--headless" ]; then
  HEADLESS=true
fi

REMOTE_NAME="gdrive"
MOUNT_POINT="/mnt/gdrive/media"
CONFIG_DIR="/etc/rclone"
CONFIG_FILE="${CONFIG_DIR}/rclone.conf"
CACHE_DIR="/mnt/data/rclone-cache"

echo "=== rclone Google Drive mount setup ==="

# 1. Install rclone
if ! command -v rclone &>/dev/null; then
  echo "Installing rclone..."
  curl -fsSL https://rclone.org/install.sh | sudo bash
else
  echo "rclone already installed: $(rclone version | head -1)"
fi

# 2. Create mount point and cache dir
sudo mkdir -p "${MOUNT_POINT}" "${CACHE_DIR}"
sudo chown -R 1000:1000 /mnt/gdrive "${CACHE_DIR}"

# 3. Configure Google Drive remote
if ! rclone listremotes --config "${CONFIG_FILE}" 2>/dev/null | grep -q "^${REMOTE_NAME}:$"; then
  echo ""
  echo "=== Google Drive configuration ==="

  if [ "$HEADLESS" = true ]; then
    echo "HEADLESS MODE - no browser on this machine."
    echo ""
    echo "You will run 'rclone config' here, but the OAuth happens on"
    echo "another machine that has a browser. Follow these steps:"
    echo ""
    echo "STEP 1: On this machine, answer the 'rclone config' prompts:"
    echo "  n                          (new remote)"
    echo "  gdrive                     (name)"
    echo "  drive                      (storage type - Google Drive)"
    echo "  <blank>                    (client_id - press Enter)"
    echo "  <blank>                    (client_secret - press Enter)"
    echo "  1                          (scope - Full access)"
    echo "  <blank>                    (root_folder_id - press Enter)"
    echo "  <blank>                    (service_account_file - press Enter)"
    echo "  n                          (edit advanced config? no)"
    echo "  n                          (use auto config? NO - this is key)"
    echo ""
    echo "STEP 2: rclone will wait for a token. On a machine WITH a browser:"
    echo "  rclone authorize \"drive\""
    echo ""
    echo "  -> browser opens -> log in to Google -> grant permission"
    echo "  -> rclone prints a JSON token like:"
    echo '     {"access_token":"ya29...","token_type":"Bearer","refresh_token":"1//0e...","expiry":"..."}'
    echo ""
    echo "STEP 3: Copy that entire JSON string, paste it at the prompt here."
    echo ""
    echo "  (rclone is now waiting for your input)"
    echo ""
  else
    echo "No '${REMOTE_NAME}' remote found. Starting interactive setup..."
    echo "Choose: drive (Google Drive) -> leave client_id/secret blank ->"
    echo "        scope 1 (Full access) -> 'Use auto config?' YES -> browser opens"
    echo ""
    echo "If this machine is headless, cancel and re-run with --headless"
    echo ""
  fi

  rclone config

  # Copy user config to system location for the systemd service
  USER_CONFIG="${HOME}/.config/rclone/rclone.conf"
  if [ -f "${USER_CONFIG}" ]; then
    sudo mkdir -p "${CONFIG_DIR}"
    sudo cp "${USER_CONFIG}" "${CONFIG_FILE}"
    sudo chmod 600 "${CONFIG_FILE}"
    echo "Copied rclone config to ${CONFIG_FILE}"
  fi
else
  echo "Remote '${REMOTE_NAME}' already configured."
fi

# 4. Install systemd unit
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo cp "${SCRIPT_DIR}/../systemd/rclone-gdrive.service" /etc/systemd/system/
sudo systemctl daemon-reload

echo ""
echo "=== Setup complete ==="
echo ""
echo "1. Create folder structure on Google Drive:"
echo "   rclone mkdir gdrive:media/movies"
echo "   rclone mkdir gdrive:media/tv"
echo ""
echo "2. Upload existing media (run from the node that has the files):"
echo "   rclone copy /path/to/movies gdrive:media/movies -P"
echo "   rclone copy /path/to/tv gdrive:media/tv -P"
echo "   # 750GB/day upload limit on personal Google Drive"
echo ""
echo "3. Start the mount:"
echo "   sudo systemctl enable --now rclone-gdrive"
echo ""
echo "4. Verify:"
echo "   systemctl status rclone-gdrive"
echo "   ls /mnt/gdrive/media/"
echo ""
echo "5. Apply updated k8s manifests:"
echo "   kubectl apply -f manifests/99-apps/media/jellyfin.yaml"
echo "   kubectl apply -f manifests/99-apps/media/radarr.yaml"
echo "   kubectl apply -f manifests/99-apps/media/sonarr.yaml"
