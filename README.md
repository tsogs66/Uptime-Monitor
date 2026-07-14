# Proxmox Monitoring LXC — Prometheus + Grafana + Uptime Kuma

A ready-to-deploy Proxmox LXC that monitors uptime and performance for
common web services, apps, sites, games, and infrastructure. It combines:

- **Prometheus** — metrics collection and alerting rules engine
- **Blackbox Exporter** — HTTP/ICMP/TCP probes for external sites, game
  services, and LAN infra (this is what actually tells you if a site is up)
- **Node Exporter** — CPU/RAM/disk metrics for the LXC host itself
- **Grafana** — dashboards, pre-wired to the Prometheus datasource
- **Uptime Kuma** — a simpler, friendlier uptime dashboard with built-in
  notifications (Discord, Telegram, email, etc.)

Everything runs as Docker containers inside one unprivileged LXC.

## 1. Deploy the container

Copy this whole folder to your Proxmox host (e.g. via `scp` or `git clone`),
then from the Proxmox shell:

```bash
cd proxmox-monitoring-lxc
chmod +x create-lxc.sh
bash create-lxc.sh
```

Optional environment variables (set before running, e.g.
`CTID=150 HOSTNAME=monitor bash create-lxc.sh`):

| Variable | Default | Meaning |
|---|---|---|
| `CTID` | next free ID | container ID |
| `HOSTNAME` | `monitoring` | container hostname |
| `STORAGE` | `local-lvm` | rootfs storage pool |
| `DISK_SIZE` | `8` (GB) | disk size |
| `MEMORY` | `2048` (MB) | RAM |
| `CORES` | `2` | vCPUs |
| `BRIDGE` | `vmbr0` | network bridge |
| `IP_CONFIG` | `dhcp` | static IP e.g. `192.168.1.50/24,gw=192.168.1.1` |

The script downloads the Debian 12 template if needed, creates the LXC,
installs Docker, copies the stack files in, and starts everything with
`docker compose up -d`. It prints the container's IP and a generated root
password at the end.

## 2. Access the services

| Service | URL | Notes |
|---|---|---|
| Grafana | `http://<IP>:3000` | login `admin` / `admin`, change password on first login |
| Prometheus | `http://<IP>:9090` | raw metrics/query UI |
| Uptime Kuma | `http://<IP>:3001` | create your admin account on first visit |

## 3. What's monitored out of the box

`prometheus/prometheus.yml` ships with Blackbox probes pre-configured for:

- **Common web services/sites**: Google, Cloudflare, GitHub, Microsoft,
  Amazon, YouTube, Wikipedia, Reddit, Netflix, Discord
- **Financial / banking / e-wallet apps** (PH-focused): GCash, Maya
  (PayMaya), BPI, BDO, Metrobank, UnionBank, RCBC, Landbank, Security Bank,
  PSBank, PNB, China Bank, GrabPay, ShopeePay, Coins.ph, PayPal — these
  check that each provider's public site/portal is reachable, not your
  account or balance
- **Games**: Steam, Epic Games, EA, Xbox, PlayStation Network, Minecraft,
  Riot Games, Battle.net
- **Local network / infrastructure** — router, NAS, servers, PCs, consoles,
  self-hosted apps — see section 3a below, this is separately editable
- **WAN / uplink health** — see section 3b below
- **The host itself**: CPU, memory, disk via Node Exporter

For the pre-built lists above (web/financial/games), edit
`prometheus/prometheus.yml` inside the container
(`/opt/monitoring/prometheus/prometheus.yml`), then:

```bash
docker compose restart prometheus
```

Alert rules for downtime, high latency, high CPU, low disk, and WAN issues
are in `prometheus/alert_rules.yml`. Wire in an Alertmanager (or Grafana
alerting, which reads the same Prometheus data) if you want notifications
from Prometheus directly — Uptime Kuma below is usually the easier path
for push notifications.

### 3a. Local network / infrastructure — edit IPs anytime, no restart

LAN devices live in two separate, easy-to-edit files instead of the main
config, so you can update IPs whenever your network changes without
touching Prometheus itself:

- `/opt/monitoring/prometheus/targets/local-icmp-targets.yml` — ping checks
  (router, gateway, modem, switches, APs, NAS, PCs, consoles, etc.)
- `/opt/monitoring/prometheus/targets/local-tcp-targets.yml` — port checks
  (management UIs, SSH, databases, game servers, self-hosted apps, etc.)

Both files come with example entries and grouping labels — replace the
example IPs with your own devices, save, and Prometheus picks up the
change automatically within ~30 seconds. No `docker compose restart`
needed.

### 3b. WAN / uplink monitoring — detect "slow" or "down" internet

Three complementary checks run continuously so you can tell a slow
connection apart from a dead one, and tell your ISP's problem apart from a
single website's problem:

- **Fast ping checks** (every 10s) to Cloudflare, Google, and Quad9 DNS —
  tracks latency and packet loss in near real time. If a router/gateway
  IP different from your LAN router is relevant (e.g. your ISP's modem
  hop), add it in the `blackbox-icmp-wan-uplink` job in `prometheus.yml`.
- **HTTP reachability checks** (every 15s) to Google and Cloudflare —
  catches cases where ping works but web traffic doesn't.
- **Real bandwidth tests** via `speedtest-exporter` (Ookla Speedtest,
  every 5 minutes, cached to avoid hammering your connection) — reports
  actual download/upload Mbps and ping, exposed as
  `speedtest_download_bits_per_second`, `speedtest_upload_bits_per_second`,
  and `speedtest_ping_latency_milliseconds`.

Alerts fire for: `WANDown` (all anchors unreachable), `WANHighLatency`,
`WANPacketLoss`, `WANSlowBandwidth` (default threshold 20 Mbps download —
edit in `alert_rules.yml` to match your actual plan speed), and
`WANHighPing`.

## 4. Set up Uptime Kuma monitors

Uptime Kuma is the friendliest place to add "is this up" checks with
built-in notification channels. After creating your admin account, add
monitors for whatever matters to you — a good starter list mirrors the
Prometheus targets above:

- HTTP(s) monitors for your important sites/apps (add your own self-hosted
  services here too — Proxmox UI, Home Assistant, Nextcloud, Plex, etc.)
- Banking/e-wallet portals (GCash, Maya, your bank's online banking) —
  useful as an early signal if a provider is having an outage
- Game service status pages (Steam, Epic, PSN, Xbox Live, Battle.net,
  Riot, Minecraft server via TCP ping on port 25565)
- TCP/ping monitors for your local infra (router, NAS, servers, SSH,
  database ports, VPN)
- A dedicated WAN monitor pinging 1.1.1.1/8.8.8.8 for a second, independent
  view of your internet uptime alongside the Prometheus/Grafana WAN alerts
- A "Group" monitor to roll several checks into one status page

Go to **Settings → Notifications** in Uptime Kuma to wire up Discord,
Telegram, email, Slack, ntfy, or 90+ other channels for alerts.

Optional: enable **Settings → Monitor History → Expose metrics** in Uptime
Kuma with an API key, then uncomment the `uptime-kuma` scrape job in
`prometheus.yml` to pull Kuma's own uptime data into Grafana too.

## 5. Import Grafana dashboards

The Prometheus datasource is pre-provisioned. Import community dashboards
via **Dashboards → New → Import** using these IDs from grafana.com:

- `7587` — Blackbox Exporter (site/service uptime & latency)
- `1860` — Node Exporter Full (host CPU/RAM/disk/network)
- `13659` — Prometheus 2.0 stats (optional, monitors Prometheus itself)
- `13756` — Speedtest Exporter (WAN download/upload/ping history over time)

## 6. Backups

All state lives in three Docker volumes: `prometheus-data`, `grafana-data`,
`uptime-kuma-data`. Snapshot the LXC in Proxmox (or back up
`/var/lib/docker/volumes/monitoring_*`) on your normal backup schedule.

## 7. Updating the stack

```bash
pct enter <CTID>
cd /opt/monitoring
docker compose pull
docker compose up -d
```
