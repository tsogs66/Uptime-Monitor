#!/usr/bin/env python3
"""
seed-uptime-kuma.py — bulk-create Uptime Kuma monitors so you don't have to
click through the UI ~90 times.

Mirrors the same target list as prometheus/prometheus.yml: web/cloud/dev
services, social & communication apps, shopping & streaming, games,
financial/banking (Philippines + international), and WAN uplink anchors.

REQUIREMENTS (one-time setup before running this):
  1. Uptime Kuma must already be running and reachable (e.g. from the
     create-lxc.sh deployment, at http://<container-IP>:3001).
  2. You must have already created your admin account through the Uptime
     Kuma web UI's first-run setup wizard. The API cannot create the very
     first account for you — Kuma requires that step happen in the browser.
  3. Install the API client:
       pip install -r requirements.txt --break-system-packages

USAGE:
  python3 seed-uptime-kuma.py \
    --url http://192.168.1.50:3001 \
    --username admin \
    --password 'your-kuma-password'

Re-running this script is safe-ish but not idempotent — it will create
duplicate monitors if you run it twice. Delete the "seeded" groups in the
Kuma UI first if you want to start over.
"""

import argparse
import sys

try:
    from uptime_kuma_api import UptimeKumaApi, MonitorType
except ImportError:
    print("Missing dependency. Run: pip install -r requirements.txt --break-system-packages", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Monitor definitions — mirrors prometheus/prometheus.yml. Edit freely.
# Each group becomes a parent "Group" monitor in Kuma; each (name, url)
# pair inside becomes a child HTTP monitor.
# ---------------------------------------------------------------------------

HTTP_GROUPS = {
    "Search, Cloud & Dev Tools": [
        ("Google", "https://www.google.com"),
        ("Bing", "https://www.bing.com"),
        ("Cloudflare", "https://www.cloudflare.com"),
        ("GitHub", "https://www.github.com"),
        ("GitLab", "https://gitlab.com"),
        ("Microsoft", "https://www.microsoft.com"),
        ("Azure", "https://azure.microsoft.com"),
        ("AWS", "https://aws.amazon.com"),
        ("Google Cloud Console", "https://console.cloud.google.com"),
        ("DigitalOcean", "https://www.digitalocean.com"),
        ("Vercel", "https://vercel.com"),
        ("npm", "https://www.npmjs.com"),
        ("Docker Hub", "https://hub.docker.com"),
        ("Wikipedia", "https://www.wikipedia.org"),
    ],
    "Social & Communication": [
        ("Facebook", "https://www.facebook.com"),
        ("Instagram", "https://www.instagram.com"),
        ("X (Twitter)", "https://www.x.com"),
        ("TikTok", "https://www.tiktok.com"),
        ("Reddit", "https://www.reddit.com"),
        ("Discord", "https://www.discord.com"),
        ("Telegram Web", "https://web.telegram.org"),
        ("WhatsApp Web", "https://web.whatsapp.com"),
        ("Messenger", "https://www.messenger.com"),
        ("Slack", "https://slack.com"),
        ("Zoom", "https://zoom.us"),
        ("Microsoft Teams", "https://teams.microsoft.com"),
        ("LinkedIn", "https://www.linkedin.com"),
    ],
    "Shopping & Streaming": [
        ("Amazon", "https://www.amazon.com"),
        ("Lazada PH", "https://www.lazada.com.ph"),
        ("Shopee PH", "https://shopee.ph"),
        ("YouTube", "https://www.youtube.com"),
        ("Netflix", "https://www.netflix.com"),
        ("Disney+", "https://www.disneyplus.com"),
        ("Prime Video", "https://www.primevideo.com"),
        ("Spotify", "https://www.spotify.com"),
        ("Twitch", "https://www.twitch.tv"),
        ("HBO Max", "https://www.hbomax.com"),
        ("iQIYI", "https://www.iqiyi.com"),
        ("Viu", "https://www.viu.com"),
    ],
    "Games": [
        ("Steam Store", "https://store.steampowered.com"),
        ("Steam Status", "https://steamstatus.com"),
        ("Epic Games Status", "https://status.epicgames.com"),
        ("Epic Games", "https://www.epicgames.com"),
        ("EA", "https://www.ea.com"),
        ("Ubisoft", "https://www.ubisoft.com"),
        ("Xbox", "https://www.xbox.com"),
        ("PlayStation Status", "https://status.playstation.com"),
        ("PlayStation", "https://www.playstation.com"),
        ("Minecraft", "https://www.minecraft.net"),
        ("Riot Games", "https://www.riotgames.com"),
        ("League of Legends", "https://www.leagueoflegends.com"),
        ("Valorant", "https://www.valorant.com"),
        ("Battle.net", "https://www.battle.net"),
        ("Roblox", "https://www.roblox.com"),
        ("Mobile Legends", "https://www.mobilelegends.com"),
        ("PUBG Mobile", "https://www.pubgmobile.com"),
        ("Call of Duty", "https://www.callofduty.com"),
        ("Rockstar Games", "https://www.rockstargames.com"),
        ("Nintendo", "https://www.nintendo.com"),
    ],
    "Financial & Banking — Philippines": [
        ("GCash", "https://www.gcash.com"),
        ("Maya", "https://www.maya.ph"),
        ("BPI", "https://www.bpi.com.ph"),
        ("BDO", "https://www.bdo.com.ph"),
        ("Metrobank", "https://www.metrobank.com.ph"),
        ("UnionBank", "https://www.unionbankph.com"),
        ("RCBC", "https://www.rcbc.com"),
        ("Landbank", "https://www.landbank.com"),
        ("Security Bank", "https://www.securitybank.com"),
        ("PSBank", "https://www.psbank.com.ph"),
        ("PNB", "https://www.pnb.com.ph"),
        ("China Bank", "https://www.chinabank.ph"),
        ("EastWest Bank", "https://www.eastwestbanker.com"),
        ("GrabPay", "https://www.grab.com/ph"),
        ("ShopeePay", "https://shopeepay.ph"),
        ("Coins.ph", "https://www.coins.ph"),
        ("GoTyme Bank", "https://www.gotyme.com.ph"),
        ("Tonik", "https://www.tonik.com"),
        ("UNO Digital Bank", "https://www.uno.bank"),
    ],
    "Financial & Banking — International": [
        ("PayPal", "https://www.paypal.com"),
        ("Wise", "https://www.wise.com"),
        ("Revolut", "https://www.revolut.com"),
        ("Chase", "https://www.chase.com"),
        ("Bank of America", "https://www.bankofamerica.com"),
        ("Wells Fargo", "https://www.wellsfargo.com"),
        ("Citibank", "https://www.citibank.com"),
        ("HSBC", "https://www.hsbc.com"),
        ("Stripe", "https://www.stripe.com"),
        ("Venmo", "https://www.venmo.com"),
        ("Cash App", "https://www.cash.app"),
        ("Coinbase", "https://www.coinbase.com"),
        ("Binance", "https://www.binance.com"),
    ],
    "WAN / Uplink (HTTP)": [
        ("Google (WAN check)", "https://www.google.com"),
        ("Cloudflare (WAN check)", "https://www.cloudflare.com"),
    ],
}

# Ping-type monitors — group name -> list of (name, hostname)
PING_GROUPS = {
    "WAN / Uplink (Ping)": [
        ("Cloudflare DNS (1.1.1.1)", "1.1.1.1"),
        ("Google DNS (8.8.8.8)", "8.8.8.8"),
        ("Quad9 DNS (9.9.9.9)", "9.9.9.9"),
    ],
    "Local Network (edit these!)": [
        ("Router / Gateway — EDIT ME", "192.168.1.1"),
    ],
}


def main():
    parser = argparse.ArgumentParser(description="Bulk-seed Uptime Kuma monitors")
    parser.add_argument("--url", required=True, help="Uptime Kuma URL, e.g. http://192.168.1.50:3001")
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--interval", type=int, default=60, help="Check interval in seconds (default 60)")
    args = parser.parse_args()

    print(f">>> Connecting to {args.url} ...")
    api = UptimeKumaApi(args.url)
    api.login(args.username, args.password)
    print(">>> Logged in.")

    total = 0

    for group_name, monitors in HTTP_GROUPS.items():
        print(f">>> Creating group: {group_name}")
        group = api.add_monitor(type=MonitorType.GROUP, name=group_name)
        group_id = group["monitorID"]
        for name, url in monitors:
            api.add_monitor(
                type=MonitorType.HTTP,
                name=name,
                url=url,
                parent=group_id,
                interval=args.interval,
                retryInterval=args.interval,
            )
            total += 1
        print(f"    added {len(monitors)} monitors")

    for group_name, monitors in PING_GROUPS.items():
        print(f">>> Creating group: {group_name}")
        group = api.add_monitor(type=MonitorType.GROUP, name=group_name)
        group_id = group["monitorID"]
        for name, hostname in monitors:
            api.add_monitor(
                type=MonitorType.PING,
                name=name,
                hostname=hostname,
                parent=group_id,
                interval=args.interval,
                retryInterval=args.interval,
            )
            total += 1
        print(f"    added {len(monitors)} monitors")

    api.disconnect()
    print(f">>> Done. Created {total} monitors across {len(HTTP_GROUPS) + len(PING_GROUPS)} groups.")
    print(">>> Go to Settings > Notifications in Uptime Kuma to wire up alerts (Discord, Telegram, email, etc.)")
    print(">>> Edit the 'Local Network' group's router IP (and add your own devices) directly in the UI.")


if __name__ == "__main__":
    main()
