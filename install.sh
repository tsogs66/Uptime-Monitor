version: "3.8"

# Prometheus + Grafana + Uptime Kuma monitoring stack
# Includes Blackbox Exporter (HTTP/ICMP/TCP probes) and Node Exporter
# (host metrics for the LXC itself).

networks:
  monitoring:
    driver: bridge

volumes:
  prometheus-data:
  grafana-data:
  uptime-kuma-data:

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    networks: [monitoring]
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/alert_rules.yml:/etc/prometheus/alert_rules.yml:ro
      - ./prometheus/targets:/etc/prometheus/targets:ro
      - prometheus-data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=30d"
      - "--web.enable-lifecycle"
    ports:
      - "9090:9090"

  blackbox-exporter:
    image: prom/blackbox-exporter:latest
    container_name: blackbox-exporter
    restart: unless-stopped
    networks: [monitoring]
    volumes:
      - ./prometheus/blackbox.yml:/etc/blackbox_exporter/config.yml:ro
    command:
      - "--config.file=/etc/blackbox_exporter/config.yml"
    ports:
      - "9115:9115"

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    networks: [monitoring]
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - "--path.procfs=/host/proc"
      - "--path.sysfs=/host/sys"
      - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
    ports:
      - "9100:9100"

  speedtest-exporter:
    image: miguelndecarvalho/speedtest-exporter:latest
    container_name: speedtest-exporter
    restart: unless-stopped
    networks: [monitoring]
    environment:
      - SPEEDTEST_CACHE_FOR=5m   # cache result so scrapes don't each trigger a new test
    ports:
      - "9798:9798"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    networks: [monitoring]
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    ports:
      - "3000:3000"
    depends_on:
      - prometheus

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    networks: [monitoring]
    volumes:
      - uptime-kuma-data:/app/data
    ports:
      - "3001:3001"
