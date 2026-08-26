#!/usr/bin/env python3
"""
Общий список источников блокировок для check-ip.py и build-blocklist.py.

Категории:
  - antifilter  — IP/подсети из реестра РКН (antifilter.download)
  - rkn_domains — домены из реестра РКН
  - cdn         — CIDR зарубежных CDN/хостингов (фактический блок)
  - geosite     — доменные списки сервисов под ТСПУ/РКН (RoscomVPN)
"""

SOURCES = {
    "antifilter": [
        ("antifilter.download — IP (резолвинг)", "https://antifilter.download/list/ip.lst"),
        ("antifilter.download - IP (/24 суммаризация)", "https://antifilter.download/list/ipsum.lst"),
        ("antifilter.download - Подсети", "https://antifilter.download/list/subnet.lst"),
    ],
    "rkn_domains": [
        ("Реестр РКН - Домены", "https://antifilter.download/list/domains.lst"),
    ],
    "cdn": [
        ("CDN-провайдеры (все)", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/all/all_plain_ipv4.txt"),
        ("CDN-провайдеры (только CDN)", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/cdn-only/cdn-only_plain_ipv4.txt"),
        ("Akamai", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/akamai/akamai_plain_ipv4.txt"),
        ("AWS CloudFront", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/aws/aws_plain_ipv4.txt"),
        ("Bunny CDN", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/bunny/bunny_plain_ipv4.txt"),
        ("CDN77", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/cdn77/cdn77_plain_ipv4.txt"),
        ("Cloudflare", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/cloudflare/cloudflare_plain_ipv4.txt"),
        ("DigitalOcean", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/digitalocean/digitalocean_plain_ipv4.txt"),
        ("Fastly", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/fastly/fastly_plain_ipv4.txt"),
        ("GCore", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/gcore/gcore_plain_ipv4.txt"),
        ("Hetzner", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/hetzner/hetzner_plain_ipv4.txt"),
        ("OVH", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/ovh/ovh_plain_ipv4.txt"),
        ("Scaleway", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/scaleway/scaleway_plain_ipv4.txt"),
        ("Vercel", "https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/vercel/vercel_plain_ipv4.txt"),
    ],
    "geosite": [
        ("RoscomVPN - YouTube", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/youtube"),
        ("RoscomVPN - Telegram", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/telegram"),
        ("RoscomVPN - GitHub", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/github"),
        ("RoscomVPN - Google Play", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/google-play"),
        ("RoscomVPN - Microsoft", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/microsoft"),
        ("RoscomVPN - Steam", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/steam"),
        ("RoscomVPN - Epic Games", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/epicgames"),
        ("RoscomVPN - Riot Games", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/riot"),
        ("RoscomVPN - Twitch", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/twitch"),
        ("RoscomVPN - Google AI", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/google-deepmind"),
        ("RoscomVPN - Торренты", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/torrent"),
        ("RoscomVPN - Windows Spy", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/win-spy"),
        ("RoscomVPN - Реклама", "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/category-ads"),
    ],
}

# Категории, чьи источники — это списки доменов (а не CIDR)
DOMAIN_CATEGORIES = {"rkn_domains", "geosite"}

# Категории, которые НЕ идут в сборку blocklist.json (тяжёлые/живые),
# а подтягиваются скриптом напрямую на лету.
# Реестр РКН доменов — 1.59M записей / ~34 МБ, раздувал бы git-историю.
LIVE_CATEGORIES = {"rkn_domains"}