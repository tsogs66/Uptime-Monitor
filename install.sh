#!/usr/bin/env bash
#
# install.sh — one-line bootstrapper for the Uptime-Monitor LXC stack.
#
# Run this ON THE PROXMOX HOST. It clones/updates the
# tsogs66/Uptime-Monitor repo into /opt, then hands off to create-lxc.sh,
# which provisions the LXC and deploys Prometheus + Grafana + Uptime Kuma.
#
# One-liner to paste into the Proxmox host shell:
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/tsogs66/Uptime-Monitor/main/install.sh)"
#
set -euo pipefail

REPO_URL="https://github.com/tsogs66/Uptime-Monitor.git"
REPO_DIR="/opt/Uptime-Monitor"

echo ">>> Uptime-Monitor installer"

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root on the Proxmox host." >&2
  exit 1
fi

if ! command -v pveversion >/dev/null 2>&1; then
  echo "pveversion not found — this doesn't look like a Proxmox VE host." >&2
  echo "Run this script on the Proxmox host shell, not inside a VM/LXC." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo ">>> Installing git ..."
  apt-get update -qq
  apt-get install -y git >/dev/null
fi

if [[ -d "$REPO_DIR/.git" ]]; then
  echo ">>> Existing checkout found at $REPO_DIR — updating ..."
  git -C "$REPO_DIR" pull --ff-only
else
  echo ">>> Cloning $REPO_URL into $REPO_DIR ..."
  git clone --depth 1 "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"
chmod +x create-lxc.sh

echo ">>> Launching create-lxc.sh ..."
exec bash create-lxc.sh