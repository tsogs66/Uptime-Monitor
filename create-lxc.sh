#!/usr/bin/env bash
#
# create-lxc.sh — Provision a Proxmox VE unprivileged LXC container
# preloaded with Docker + Docker Compose, ready to run the
# Prometheus + Grafana + Uptime Kuma monitoring stack.
#
# RUN THIS SCRIPT ON THE PROXMOX HOST (not inside a container/VM).
#
# Usage:
#   bash create-lxc.sh
#
# After it finishes, it prints the container IP and next steps.

set -euo pipefail

# Print a clear error (with line number and the command that failed) instead
# of dying silently — every earlier failure of this script exited with zero
# output because nothing caught it. This trap fixes that permanently.
trap 'echo ">>> ERROR: script failed at line $LINENO. Last command: $BASH_COMMAND" >&2' ERR

echo ">>> Starting Uptime-Monitor LXC installer..."

# ---------------------------------------------------------------------------
# Configuration — edit these to taste before running, or export as env vars
# ---------------------------------------------------------------------------

# Resolve next free container ID. Prefer pvesh; if that's unavailable or
# fails for any reason, fall back to scanning existing VM/CT IDs directly
# instead of aborting the whole script.
if [[ -z "${CTID:-}" ]]; then
  echo ">>> Determining next free container ID..."
  if command -v pvesh >/dev/null 2>&1 && CTID_AUTO="$(pvesh get /cluster/nextid 2>/dev/null)"; then
    CTID="$CTID_AUTO"
  else
    echo ">>> pvesh unavailable or failed — falling back to manual ID scan..."
    USED_IDS="$( { pct list 2>/dev/null | awk 'NR>1 {print $1}'; qm list 2>/dev/null | awk 'NR>1 {print $1}'; } | sort -n | tail -1)"
    CTID=$(( ${USED_IDS:-100} + 1 ))
  fi
fi
echo ">>> Using container ID: $CTID"

# NOTE: intentionally named CT_HOSTNAME, not HOSTNAME — bash auto-populates
# $HOSTNAME with the current machine's hostname (e.g. "pve"), so using
# HOSTNAME here would silently ignore the "monitoring" default.
CT_HOSTNAME="${CT_HOSTNAME:-monitoring}"
STORAGE="${STORAGE:-local-lvm}"          # storage pool for the rootfs
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"  # storage pool holding CT templates
DISK_SIZE="${DISK_SIZE:-64}"             # GB
MEMORY="${MEMORY:-8192}"                 # MB
SWAP="${SWAP:-512}"                      # MB
CORES="${CORES:-2}"
BRIDGE="${BRIDGE:-vmbr0}"
IP_CONFIG="${IP_CONFIG:-dhcp}"           # e.g. "192.168.1.50/24,gw=192.168.1.1" or "dhcp"
TEMPLATE="${TEMPLATE:-debian-12-standard_12.7-1_amd64.tar.zst}"
PASSWORD="${PASSWORD:-}"                 # leave blank to auto-generate

# ---------------------------------------------------------------------------
if [[ -z "$PASSWORD" ]]; then
  # "|| true" prevents a false-positive failure: head closes the pipe after
  # 20 bytes, which sends tr a SIGPIPE (exit 141) even though the password
  # was generated correctly — with pipefail on, that would otherwise abort
  # the whole script.
  PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true)"
fi

echo ">>> Checking template availability..."
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE"; then
  echo ">>> Downloading template $TEMPLATE ..."
  pveam update
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
fi

echo ">>> Creating LXC $CTID ($CT_HOSTNAME) ..."
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "$CT_HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --swap "$SWAP" \
  --rootfs "${STORAGE}:${DISK_SIZE}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CONFIG},firewall=1" \
  --unprivileged 1 \
  --features "nesting=1,keyctl=1" \
  --onboot 1 \
  --password "$PASSWORD"

echo ">>> Starting container ..."
pct start "$CTID"
sleep 8

echo ">>> Installing Docker, Docker Compose, and the monitoring stack inside the container ..."
pct exec "$CTID" -- bash -c '
set -e
apt-get update
apt-get install -y ca-certificates curl gnupg git

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
mkdir -p /opt/monitoring
'

echo ">>> Copying monitoring stack files into the container ..."
STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pct push "$CTID" "${STACK_DIR}/docker-compose.yml" /opt/monitoring/docker-compose.yml
pct push "$CTID" "${STACK_DIR}/.env.example" /opt/monitoring/.env
pct exec "$CTID" -- mkdir -p /opt/monitoring/prometheus/targets /opt/monitoring/grafana/provisioning/datasources /opt/monitoring/grafana/provisioning/dashboards
pct push "$CTID" "${STACK_DIR}/prometheus/prometheus.yml" /opt/monitoring/prometheus/prometheus.yml
pct push "$CTID" "${STACK_DIR}/prometheus/alert_rules.yml" /opt/monitoring/prometheus/alert_rules.yml
pct push "$CTID" "${STACK_DIR}/prometheus/blackbox.yml" /opt/monitoring/prometheus/blackbox.yml
pct push "$CTID" "${STACK_DIR}/prometheus/targets/local-icmp-targets.yml" /opt/monitoring/prometheus/targets/local-icmp-targets.yml
pct push "$CTID" "${STACK_DIR}/prometheus/targets/local-tcp-targets.yml" /opt/monitoring/prometheus/targets/local-tcp-targets.yml
pct push "$CTID" "${STACK_DIR}/grafana/provisioning/datasources/datasource.yml" /opt/monitoring/grafana/provisioning/datasources/datasource.yml
pct push "$CTID" "${STACK_DIR}/grafana/provisioning/dashboards/dashboards.yml" /opt/monitoring/grafana/provisioning/dashboards/dashboards.yml

echo ">>> Launching the stack ..."
pct exec "$CTID" -- bash -c 'cd /opt/monitoring && docker compose up -d'

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')

cat <<EOF

=========================================================================
 Monitoring LXC ready!  (CTID: $CTID, hostname: $CT_HOSTNAME)
 Root password: $PASSWORD

 Container IP: $IP

 Services:
   Grafana:      http://$IP:3000    (login: admin / admin — change on first login)
   Prometheus:   http://$IP:9090
   Uptime Kuma:  http://$IP:3001    (create your admin account on first visit)

 To add your LAN devices (router, NAS, PCs, game consoles, self-hosted
 apps), edit these files inside the container — no restart needed, changes
 are picked up automatically within ~30s:
   /opt/monitoring/prometheus/targets/local-icmp-targets.yml   (ping checks)
   /opt/monitoring/prometheus/targets/local-tcp-targets.yml    (port checks)

 For everything else (web services, banking/e-wallet apps, games, WAN
 anchors), edit /opt/monitoring/prometheus/prometheus.yml, then run:
   docker compose restart prometheus

 WAN/uplink health (latency, packet loss, down detection, real speedtest)
 is monitored automatically — see Grafana for WAN dashboards, or query
 speedtest_download_bits_per_second / probe_success{group="wan"} directly.

 Uptime Kuma monitors are configured through its web UI — see README.md
 for a starter checklist of common services/games/infra/financial apps.
=========================================================================
EOF
