#!/usr/bin/env python3
"""
IP Block Checker for Russian Blocklists
Checks if an IP/domain is in Roskomnadzor or CDN blocklists.

Usage:
  python3 check-ip.py [IP or domain]
  curl -sL https://raw.githubusercontent.com/YOU/YOUR_REPO/main/check-ip.py | python3 - [IP]
"""
import urllib.request
import ssl
import sys
import io
import ipaddress
import socket
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

# Fix encoding on Windows
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# ─── Config ───────────────────────────────────────────────────────────────────
TIMEOUT = 15
MAX_WORKERS = 8

SOURCES = {
    "antifilter": [
        ("antifilter.download — IP (резолвинг)", "https://antifilter.download/list/ip.lst"),
        ("antifilter.download — IP (/24 суммаризация)", "https://antifilter.download/list/ipsum.lst"),
        ("antifilter.download — Подсети", "https://antifilter.download/list/subnet.lst"),
    ],
    "rkn_domains": [
        ("Реестр РКН — Домены", "https://antifilter.download/list/domains.lst"),
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
}

ASN_NAMES = {
    "AS13335": "Cloudflare", "AS15169": "Google", "AS16509": "Amazon (AWS)",
    "AS8075": "Microsoft", "AS14061": "DigitalOcean", "AS24940": "Hetzner",
    "AS16276": "OVH", "AS20940": "Akamai", "AS54113": "Fastly",
    "AS200325": "Bunny CDN", "AS60068": "CDN77", "AS199524": "GCore",
    "AS212238": "Vercel (DataCamp)", "AS31898": "Oracle Cloud",
    "AS14618": "Amazon (AWS)", "AS14935": "Contabo", "AS51167": "Contabo",
    "AS213230": "Hetzner", "AS12876": "Scaleway", "AS29447": "Scaleway",
    "AS20473": "Vultr (Constant)", "AS396356": "M247", "AS48693": "Reba",
    "AS58061": "Scalaxy", "AS44907": "GlobalTeleHost", "AS56630": "MelBiCom",
    "AS8849": "MelBiCom", "AS202422": "GCore", "AS63023": "GTHost",
    "AS42708": "GleSYS", "AS53667": "BuyVM", "AS32934": "Meta (Facebook)",
    "AS62041": "Telegram", "AS62014": "Telegram", "AS211157": "Telegram",
    "AS59930": "Telegram", "AS36458": "X (Twitter)", "AS13414": "X (Twitter)",
    "AS55002": "Reba/Ukraine", "AS209103": "Selectel", "AS49505": "Selectel",
    "AS174": "Cogent", "AS3356": "Lumen (Level3)",
}

# ─── Helpers ──────────────────────────────────────────────────────────────────

def get(url, binary=False):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url, headers={"User-Agent": "Cheburcheck-Script/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as r:
            data = r.read()
            return data if binary else data.decode("utf-8", errors="replace")
    except Exception:
        return None

def parse_cidrs(text):
    networks = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "/" in line:
            try:
                networks.append(ipaddress.ip_network(line, strict=False))
            except ValueError:
                pass
        elif "." in line or ":" in line:
            try:
                networks.append(ipaddress.ip_network(line, strict=False))
            except ValueError:
                pass
    return networks

def check_ip_in_networks(ip, networks):
    addr = ipaddress.ip_address(ip)
    matches = []
    for net in networks:
        if addr in net:
            matches.append(str(net))
    return matches

def resolve_domain(domain):
    ips = set()
    for family in (socket.AF_INET, socket.AF_INET6):
        try:
            for info in socket.getaddrinfo(domain, None, family):
                ips.add(info[4][0])
        except socket.gaierror:
            pass
    return list(ips)

def detect_ip_version(ip):
    return "ipv6" if ":" in ip else "ipv4"

def get_asn_info(ip):
    # Try bgp.tools API (free, no key needed)
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        req = urllib.request.Request(
            f"https://bgp.tools/prefix/{ip}",
            headers={"User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(req, timeout=10, context=ctx) as r:
            # bgp.tools returns HTML, parse ASN from it
            html = r.read().decode("utf-8", errors="replace")
            # Look for AS number pattern
            import re
            as_match = re.search(r'AS(\d+)', html)
            if as_match:
                asn = f"AS{as_match.group(1)}"
                # Try to find org name
                org_match = re.search(r'<td[^>]*>Organization</td>\s*<td[^>]*>([^<]+)', html)
                org = org_match.group(1).strip() if org_match else None
                return asn, org
    except Exception:
        pass

    # Fallback: try whois
    try:
        r = subprocess.run(["whois", ip], capture_output=True, text=True, timeout=10)
        if r.returncode == 0:
            asn = None
            org = None
            for line in r.stdout.splitlines():
                line_s = line.strip()
                if not asn and ("OriginAS:" in line_s or "origin:" in line_s.lower()):
                    parts = line_s.split(":", 1)
                    if len(parts) == 2:
                        val = parts[1].strip().replace("AS", "").strip()
                        if val.isdigit():
                            asn = f"AS{val}"
                if not org and ("OrgName:" in line_s or "netname:" in line_s.lower()):
                    parts = line_s.split(":", 1)
                    if len(parts) == 2:
                        org = parts[1].strip()
            return asn, org
    except Exception:
        pass

    return None, None

def format_number(n):
    return f"{n:,}".replace(",", " ")

# ─── Color helpers ────────────────────────────────────────────────────────────

class C:
    RED = "\033[91m"
    GRN = "\033[92m"
    YLW = "\033[93m"
    BLU = "\033[94m"
    CYN = "\033[96m"
    BLD = "\033[1m"
    DIM = "\033[2m"
    RST = "\033[0m"

def pr(color, text, indent=0):
    prefix = "  " * indent
    print(f"{prefix}{color}{text}{C.RST}")

def section(text):
    print()
    pr(C.CYN, f"── {text} {'─' * (56 - len(text))}")

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    print()
    pr(C.BLD, "╔══════════════════════════════════════════════════════════════╗")
    pr(C.BLD, "║           IP BLOCK CHECKER — Russia & CDN Lists            ║")
    pr(C.BLD, "╚══════════════════════════════════════════════════════════════╝")

    target = sys.argv[1] if len(sys.argv) > 1 else None

    if not target:
        pr(C.DIM, "  Определяю внешний IP...")
        for svc in ["https://api.ipify.org", "https://ifconfig.me", "https://icanhazip.com"]:
            try:
                ctx = ssl.create_default_context()
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE
                req = urllib.request.Request(svc, headers={"User-Agent": "curl/7.88"})
                with urllib.request.urlopen(req, timeout=8, context=ctx) as r:
                    target = r.read().decode().strip()
                    break
            except Exception:
                continue
        if not target:
            pr(C.RED, "  X Не удалось определить внешний IP. Укажите вручную.")
            sys.exit(1)
        pr(C.GRN, f"  Внешний IP: {target}")

    is_domain = any(c.isalpha() for c in target) and "." in target and not target.replace(".", "").replace(":", "").isdigit()
    check_ips = []
    domain_name = None

    if is_domain:
        domain_name = target
        pr(C.BLU, f"\n  Домен: {target}")
        check_ips = resolve_domain(target)
        if not check_ips:
            pr(C.RED, f"  X Не удалось разрезолвить домен {target}")
            sys.exit(1)
        pr(C.GRN, f"  -> IP: {', '.join(check_ips)}")
    else:
        check_ips = [target]
        pr(C.BLU, f"\n  IP-адрес: {target}")
        pr(C.DIM, f"  Тип: {detect_ip_version(target).upper()}")

    # ASN lookup
    section("ASN / Провайдер")
    for check_ip in check_ips:
        if ":" in check_ip:
            continue
        pr(C.DIM, f"  Запрос информации о {check_ip}...")
        asn, org = get_asn_info(check_ip)
        if asn:
            friendly = ASN_NAMES.get(asn, "")
            pr(C.BLD, f"  ASN:    {asn}" + (f" ({friendly})" if friendly else ""))
        if org:
            pr(C.BLD, f"  Орг:    {org}")
        if not asn and not org:
            pr(C.DIM, "  ASN не определён (сервисы whois/bgptools недоступны)")

    # Download blocklists
    section("Загрузка списков блокировок")
    all_networks = {}
    total_networks = 0
    domain_list = []

    def download_source(name, url):
        content = get(url)
        if content is None:
            return name, None, 0, None
        if url.endswith("domains.lst"):
            return name, None, 0, content
        networks = parse_cidrs(content)
        return name, networks, len(networks), None

    tasks = []
    for category, sources in SOURCES.items():
        for name, url in sources:
            tasks.append((name, url))

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {pool.submit(download_source, n, u): n for n, u in tasks}
        done = 0
        for future in as_completed(futures):
            done += 1
            name, networks, count, domains = future.result()
            if networks is None and domains is None:
                pr(C.DIM, f"  [{done}/{len(tasks)}] {name}: ошибка загрузки")
                all_networks[name] = []
            elif domains is not None:
                pr(C.GRN, f"  [{done}/{len(tasks)}] {name}: доменов в списке")
                domain_list = domains.splitlines()
            else:
                pr(C.GRN, f"  [{done}/{len(tasks)}] {name}: {format_number(count)} CIDR")
                all_networks[name] = networks
                total_networks += count

    pr(C.DIM, f"\n  Всего загружено: {format_number(total_networks)} CIDR-записей")

    # Check IP against all lists
    section("Проверка IP")

    antifilter_blocked = False
    cdn_blocked = False
    cdn_providers = set()
    domain_blocked = False
    all_matches = {}

    for check_ip in check_ips:
        pr(C.DIM, f"  Проверяю {check_ip}...")

        for source_name, networks in all_networks.items():
            if not networks:
                continue
            matches = check_ip_in_networks(check_ip, networks)
            if matches:
                all_matches[source_name] = matches[:3]

                for cat, sources in SOURCES.items():
                    for sname, _ in sources:
                        if sname == source_name:
                            if cat == "antifilter":
                                antifilter_blocked = True
                            elif cat == "cdn":
                                cdn_blocked = True
                                cdn_providers.add(source_name)

    # Domain check
    if domain_name and domain_list:
        domain_lower = domain_name.lower()
        for d in domain_list:
            d = d.strip().lower()
            if d and (domain_lower == d or domain_lower.endswith("." + d)):
                domain_blocked = True
                break

    # Results
    section("Результат")

    is_clean = not antifilter_blocked and not cdn_blocked and not domain_blocked

    if is_clean:
        pr(C.GRN, C.BLD, 1)
        pr(C.GRN, "  V ЧИСТ", 1)
        pr(C.GRN, "  IP-адрес не найден ни в одном списке блокировок", 1)
        pr(C.GRN, "  Ограничений на территории РФ не обнаружено", 1)
    else:
        pr(C.RED, C.BLD, 1)
        pr(C.RED, "  X ЗАБЛОКИРОВАН", 1)

        if antifilter_blocked:
            pr(C.RED, "", 1)
            pr(C.RED, "  > Реестр РКН (antifilter.download):", 1)
            for src_name, matches in all_matches.items():
                for cat, sources in SOURCES.items():
                    if cat == "antifilter":
                        for sname, _ in sources:
                            if sname == src_name:
                                pr(C.RED, f"    - {src_name}", 2)
                                for m in matches[:2]:
                                    pr(C.DIM, f"      {m}", 2)

        if cdn_blocked:
            pr(C.RED, "", 1)
            pr(C.RED, "  > CDN / Хостинг (фактическая блокировка):", 1)
            for src_name, matches in all_matches.items():
                for cat, sources in SOURCES.items():
                    if cat == "cdn":
                        for sname, _ in sources:
                            if sname == src_name:
                                pr(C.RED, f"    - {src_name}", 2)
                                for m in matches[:2]:
                                    pr(C.DIM, f"      {m}", 2)

        if domain_blocked:
            pr(C.RED, "", 1)
            pr(C.RED, "  > Домен в реестре РКН:", 1)
            pr(C.RED, f"    Домен {domain_name} найден в списке заблокированных", 2)

    # CDN provider summary
    if cdn_providers:
        section("CDN / Хостинг")
        for p in sorted(cdn_providers):
            clean = p.split(" — ")[0] if " — " in p else p
            pr(C.YLW, f"  * {clean}")
        if any("Cloudflare" in p for p in cdn_providers):
            pr(C.DIM, "    -> Cloudflare CDN (CDN-блок: трафик режется на 16-20 КБ)")
        elif any("AWS" in p for p in cdn_providers):
            pr(C.DIM, "    -> Amazon CloudFront / AWS")
        elif any("Hetzner" in p for p in cdn_providers):
            pr(C.DIM, "    -> Хостинг Hetzner (подсеть в блок-листе CDN)")

    # Verdict
    section("Итого")
    pr(C.BLD, "  " + "-" * 54)
    if is_clean:
        pr(C.GRN, C.BLD, 1)
        pr(C.GRN, "  ВЕРДИКТ: ЧИСТ - ограничений не обнаружено", 1)
    else:
        issues = []
        if antifilter_blocked:
            issues.append("реестр РКН")
        if cdn_blocked:
            issues.append("CDN-блок")
        if domain_blocked:
            issues.append("домен в реестре")
        pr(C.RED, C.BLD, 1)
        pr(C.RED, f"  ВЕРДИКТ: ЗАБЛОКИРОВАН - {', '.join(issues)}", 1)
    pr(C.BLD, "  " + "-" * 54)
    print()

if __name__ == "__main__":
    main()
