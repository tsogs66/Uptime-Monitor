# =============================================================================
# LOCAL NETWORK / INFRASTRUCTURE — TCP port-check targets
# =============================================================================
# Edit this file to add/remove specific services running on your LAN
# (format: host:port). Prometheus watches this file and picks up changes
# automatically — NO restart or reload needed, just save the file.
#
# Replace the examples below with your actual services.
# =============================================================================

- targets:
    - 192.168.1.1:80         # <- router web UI (http)
    - 192.168.1.10:8006      # <- Proxmox web UI (https, uses tcp_connect just for reachability)
    - 192.168.1.10:22        # <- SSH on the Proxmox host
  labels:
    group: "infra"
    name: "management-ports"

- targets:
    - 192.168.1.11:445       # <- NAS (SMB)
    - 192.168.1.11:5000      # <- NAS web UI (e.g. Synology DSM)
  labels:
    group: "infra"
    name: "nas"

- targets: []
    # - 192.168.1.20:3306    # <- MySQL / MariaDB
    # - 192.168.1.20:5432    # <- PostgreSQL
    # - 192.168.1.30:25565   # <- Minecraft server
    # - 192.168.1.30:27015   # <- Source engine game server (CS, TF2, etc.)
    # - 192.168.1.40:1194    # <- OpenVPN
    # - 192.168.1.40:51820   # <- WireGuard (note: UDP — tcp_connect won't work, use a different check)
  labels:
    group: "apps"
    name: "self-hosted-apps"
