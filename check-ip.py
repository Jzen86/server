#!/usr/bin/env python3
"""
IP Block Checker for Russian Blocklists
Checks if an IP/domain is in Roskomnadzor or CDN blocklists.

Использует готовую базу blocklist.json (генерируется build-blocklist.py
в GitHub Actions и коммитится в репо). Скрипт качает свежий файл
одним запросом — быстро и всегда актуально. Тяжёлый реестр РКН
доменов (1.59M записей) тянется напрямую с antifilter.download на лету.

Usage:
  python3 check-ip.py [IP or domain]
  python3 check-ip.py [IP or domain] --db /path/to/blocklist.json
"""
import urllib.request
import ssl
import sys
import os
import io
import json
import ipaddress
import socket
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

# Fix encoding on Windows
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# ─── Config ───────────────────────────────────────────────────────────────────
TIMEOUT = 20
MAX_WORKERS = 8

# Готовая база в репо (генерируется build-blocklist.py + GitHub Actions)
DB_URL = "https://raw.githubusercontent.com/Jzen86/server/main/blocklist.json"
LOCAL_DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocklist.json")

# Живой источник реестра РКН доменов (тяжёлый — не идёт в базу, тянем на лету)
RKN_DOMAINS_URL = "https://antifilter.download/list/domains.lst"

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


def load_db(db_path=None):
    """Загружает базу: локальный файл или скачивает DB_URL."""
    local = db_path or LOCAL_DB
    if db_path:
        if not os.path.exists(db_path):
            print(f"  X Файл базы не найден: {db_path}")
            sys.exit(1)
        with open(db_path, "r", encoding="utf-8") as f:
            return json.load(f)
    if os.path.exists(local):
        with open(local, "r", encoding="utf-8") as f:
            return json.load(f)
    pr(C.DIM, "  Скачиваю свежую базу blocklist.json...")
    content = get(DB_URL)
    if content is None:
        print("  X Не удалось скачать базу. Используйте --db с локальным файлом.")
        sys.exit(1)
    return json.loads(content)


def networks_for_source(cidr_list):
    return [ipaddress.ip_network(c, strict=False) for c in cidr_list]


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
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        req = urllib.request.Request(
            f"https://bgp.tools/prefix/{ip}",
            headers={"User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(req, timeout=10, context=ctx) as r:
            html = r.read().decode("utf-8", errors="replace")
            import re
            as_match = re.search(r'AS(\d+)', html)
            if as_match:
                asn = f"AS{as_match.group(1)}"
                org_match = re.search(r'<td[^>]*>Organization</td>\s*<td[^>]*>([^<]+)', html)
                org = org_match.group(1).strip() if org_match else None
                return asn, org
    except Exception:
        pass

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
    args = [a for a in sys.argv[1:]]
    db_path = None
    if "--db" in args:
        i = args.index("--db")
        db_path = args[i + 1]
        del args[i:i + 2]
    target = args[0] if args else None

    print()
    pr(C.BLD, "╔══════════════════════════════════════════════════════════════╗")
    pr(C.BLD, "║           IP BLOCK CHECKER — Russia & CDN Lists            ║")
    pr(C.BLD, "╚══════════════════════════════════════════════════════════════╝")

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

    # ── Цель ──
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

    # ── ASN ──
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

    # ── Загрузка базы ──
    section("Загрузка базы блокировок")
    db = load_db(db_path)
    data = db.get("data", {})
    generated = db.get("generated", "?")
    n_sources = len(db.get("sources", []))
    pr(C.GRN, f"  База v{db.get('version', 1)} | источников: {n_sources} | обновлена: {generated}")
    if db.get("errors"):
        pr(C.YLW, f"  (пропущено источников с ошибкой: {len(db['errors'])})")

    # Кэшируем сети по категориям
    net_cache = {}
    for cat in ("antifilter", "cdn"):
        net_cache[cat] = {
            src: networks_for_source(cidrs)
            for src, cidrs in data.get(cat, {}).items()
        }

    # ── Проверка IP ──
    section("Проверка IP")

    antifilter_blocked = False
    cdn_blocked = False
    cdn_providers = set()
    all_matches = {}

    for check_ip in check_ips:
        pr(C.DIM, f"  Проверяю {check_ip}...")
        for cat in ("antifilter", "cdn"):
            for src, nets in net_cache[cat].items():
                matches = check_ip_in_networks(check_ip, nets)
                if matches:
                    all_matches[src] = matches[:3]
                    if cat == "antifilter":
                        antifilter_blocked = True
                    elif cat == "cdn":
                        cdn_blocked = True
                        cdn_providers.add(src)

    # ── Проверка домена ──
    domain_blocked = False
    domain_matched_sources = []
    if domain_name:
        domain_lower = domain_name.lower()
        # Реестр РКН (живой, тянем напрямую)
        pr(C.DIM, "  Проверяю домен в реестре РКН (antifilter.download)...")
        rkn_content = get(RKN_DOMAINS_URL)
        if rkn_content:
            for line in rkn_content.splitlines():
                d = line.strip().lower()
                if not d or d.startswith("#"):
                    continue
                if d.startswith("domain:"):
                    d = d[7:]
                if d and (domain_lower == d or domain_lower.endswith("." + d)):
                    domain_blocked = True
                    domain_matched_sources.append("Реестр РКН - Домены")
                    break
        else:
            pr(C.DIM, "  (реестр РКН недоступен, проверяю только по geosite)")
        # Geosite из базы
        if not domain_blocked:
            for src, domains in data.get("geosite", {}).items():
                for d in domains:
                    if domain_lower == d or domain_lower.endswith("." + d):
                        domain_blocked = True
                        domain_matched_sources.append(src)
                        break
                if domain_blocked:
                    break

    # ── Результат ──
    section("Результат")

    is_clean = not antifilter_blocked and not cdn_blocked and not domain_blocked

    if is_clean:
        pr(C.GRN, "  V ЧИСТ", 1)
        pr(C.GRN, "  IP-адрес не найден ни в одном списке блокировок", 1)
        pr(C.GRN, "  Ограничений на территории РФ не обнаружено", 1)
    else:
        pr(C.RED, "  X ЗАБЛОКИРОВАН", 1)

        if antifilter_blocked:
            pr(C.RED, "  > Реестр РКН (IP/подсети):", 1)
            for src_name, matches in all_matches.items():
                if src_name in net_cache.get("antifilter", {}):
                    pr(C.RED, f"    - {src_name}", 2)
                    for m in matches[:2]:
                        pr(C.DIM, f"      {m}", 2)

        if cdn_blocked:
            pr(C.RED, "  > CDN / Хостинг (фактическая блокировка):", 1)
            for src_name, matches in all_matches.items():
                if src_name in net_cache.get("cdn", {}):
                    pr(C.RED, f"    - {src_name}", 2)
                    for m in matches[:2]:
                        pr(C.DIM, f"      {m}", 2)

        if domain_blocked:
            pr(C.RED, "  > Домен найден в списках блокировок:", 1)
            for src in domain_matched_sources:
                pr(C.RED, f"    - {src}", 2)
            pr(C.RED, f"    Домен {domain_name} заблокирован", 2)

    # ── CDN summary ──
    if cdn_providers:
        section("CDN / Хостинг")
        for p in sorted(cdn_providers):
            clean = p.split(" - ")[0] if " - " in p else p
            pr(C.YLW, f"  * {clean}")
        if any("Cloudflare" in p for p in cdn_providers):
            pr(C.DIM, "    -> Cloudflare CDN (CDN-блок: трафик режется на 16-20 КБ)")
        elif any("AWS" in p for p in cdn_providers):
            pr(C.DIM, "    -> Amazon CloudFront / AWS")
        elif any("Hetzner" in p for p in cdn_providers):
            pr(C.DIM, "    -> Хостинг Hetzner (подсеть в блок-листе CDN)")

    # ── Итого ──
    section("Итого")
    pr(C.BLD, "  " + "-" * 54)
    if is_clean:
        pr(C.GRN, "  ВЕРДИКТ: ЧИСТ - ограничений не обнаружено", 1)
    else:
        issues = []
        if antifilter_blocked:
            issues.append("реестр РКН (IP)")
        if cdn_blocked:
            issues.append("CDN-блок")
        if domain_blocked:
            issues.append("домен в списках")
        pr(C.RED, f"  ВЕРДИКТ: ЗАБЛОКИРОВАН - {', '.join(issues)}", 1)
    pr(C.BLD, "  " + "-" * 54)
    print()

if __name__ == "__main__":
    main()