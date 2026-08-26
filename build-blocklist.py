#!/usr/bin/env python3
"""
Сборщик базы блокировок.

Скачивает все источники из blocklists.py, разбирает их и пишет
единый файл blocklist.json. Запускается по cron в GitHub Actions.

Выходной формат:
{
  "version": 1,
  "generated": "2026-08-26T12:00:00Z",
  "categories": {
     "antifilter": ["CIDR", ...],
     "cdn":        ["CIDR", ...],
     "rkn_domains": ["domain", ...],
     "geosite":    ["domain", ...]
  },
  "sources": [ {"name": ..., "category": ..., "count": N}, ... ]
}

Домены нормализуются: убирается префикс "domain:", регистр в нижний,
без ведущей точки. Для geosite также сохраняется суффиксное совпадение
(поддомены), поэтому храним и запись, и префикс ".". Для rkn_domains —
просто домен.
"""
import urllib.request
import ssl
import json
import sys
import os
import io
import ipaddress
import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

import blocklists

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

TIMEOUT = 30
MAX_WORKERS = 12

# Выходной файл
OUTPUT = "blocklist.json"


def get(url):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url, headers={"User-Agent": "BlocklistBuilder/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as r:
            return r.read().decode("utf-8", errors="replace")
    except Exception as e:
        return None


def parse_cidrs(text):
    nets = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or " " in line:
            continue
        try:
            net = ipaddress.ip_network(line, strict=False)
            nets.add(str(net))
        except ValueError:
            # пробуем как голый IP
            try:
                net = ipaddress.ip_network(line, strict=False)
                nets.add(str(net))
            except ValueError:
                pass
    return nets


def parse_domains(text, rkn_style=False):
    """Возвращает множество доменов. rkn_style=True — plain домены (реестр)."""
    domains = set()
    for line in text.splitlines():
        line = line.strip().lower()
        if not line or line.startswith("#"):
            continue
        if line.startswith("domain:"):
            line = line[7:]
        elif line.startswith("full:"):
            line = line[5:]
        elif line.startswith("keyword:"):
            continue
        # обрезаем wildcard/операторы
        if line.startswith("*.") or line.startswith("."):
            line = line.lstrip("*.")
        # убираем порт/хвосты
        if "/" in line:
            line = line.split("/")[0]
        if not line or "." not in line:
            continue
        if any(ch in line for ch in " *[]{}|"):
            continue
        domains.add(line.strip("."))
    return domains


def build():
    tasks = []
    for category, sources in blocklists.SOURCES.items():
        if category in blocklists.LIVE_CATEGORIES:
            continue
        for name, url in sources:
            tasks.append((name, url, category))

    results = {}  # name -> (category, {set of cidrs} | {set of domains})
    errors = []

    def fetch(task):
        name, url, category = task
        content = get(url)
        if content is None:
            return name, category, None, None
        if category in blocklists.DOMAIN_CATEGORIES:
            rkn = (category == "rkn_domains")
            data = parse_domains(content, rkn_style=rkn)
            return name, category, None, data
        else:
            data = parse_cidrs(content)
            return name, category, data, None

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {pool.submit(fetch, t): t[0] for t in tasks}
        done = 0
        for fut in as_completed(futures):
            done += 1
            name, category, cidrs, domains = fut.result()
            if cidrs is None and domains is None:
                errors.append(name)
                print(f"  [ERR ] {name}: загрузка не удалась", file=sys.stderr)
            else:
                results[name] = (category, cidrs if cidrs is not None else domains)
                kind = "CIDR" if cidrs is not None else "доменов"
                count = len(cidrs) if cidrs is not None else len(domains)
                print(f"  [{done:3}/{len(tasks)}] {name}: {count} {kind}")

    # Собираем по категориям: имя источника -> [данные]
    # Для rkn_domains плоский список (источник один — реестр)
    data = {}
    for cat in blocklists.SOURCES:
        data[cat] = {}
    for name, (category, dataset) in results.items():
        data.setdefault(category, {})[name] = sorted(dataset)

    source_meta = [
        {"name": name, "category": cat, "count": len(items)}
        for cat, srcs in data.items()
        for name, items in srcs.items()
    ]

    payload = {
        "version": 1,
        "generated": datetime.datetime.now(datetime.timezone.utc)
                            .isoformat(timespec="seconds")
                            .replace("+00:00", "Z"),
        "data": data,
        "sources": source_meta,
        "errors": sorted(errors),
    }

    tmp = OUTPUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, OUTPUT)

    # Статистика
    print()
    def cat_len(cat):
        return sum(len(v) for v in data.get(cat, {}).values())
    total_cidr = cat_len("antifilter") + cat_len("cdn")
    total_dom = cat_len("rkn_domains") + cat_len("geosite")
    print(f"Готово: {total_cidr} CIDR, {total_dom} доменов")
    print(f"Файл: {OUTPUT} ({os.path.getsize(OUTPUT)/1024:.0f} КБ)")
    for cat in ("antifilter", "cdn", "rkn_domains", "geosite"):
        print(f"  {cat}: {cat_len(cat)}")
    if errors:
        print(f"Ошибки ({len(errors)}): {', '.join(errors)}", file=sys.stderr)


if __name__ == "__main__":
    build()