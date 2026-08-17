# Server Utils

Набор bash-скриптов для проверки VPS-сервера: геолокация IP и то, как его видят зарубежные сервисы.

## Скрипты

| Скрипт | Назначение |
|---|---|
| `server-check.sh` | Меню: запуск `check-location.sh`, `check-services.sh` или обоих по очереди |
| `check-location.sh` | Геолокация IP по 18 GeoIP-базам, подсчёт голосов, вердикт «ЧИСТЫЙ/ГРЯЗНЫЙ» |
| `check-services.sh` | Как IP видят Google, топ ИИ и сервисы, ушедшие из РФ |

## Требования

- Linux VPS с `curl` и `jq`: `apt install -y curl jq`

## Запуск (без установки)

Меню всех проверок (`server-check.sh`):

```bash
bash <(curl -sL https://raw.githubusercontent.com/Jzen86/server/main/server-check.sh)
```

При выборе 1 запустится `check-location.sh`, при выборе 2 — `check-services.sh`, при выборе 3 — оба по очереди, 0 — выход.

Геолокация IP напрямую:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Jzen86/server/main/check-location.sh)
```

Проверка сервисов:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Jzen86/server/main/check-services.sh)
```

## Как читать вывод

**check-location** — 18 GeoIP-баз голосуют за страну IP. Если базы единодушны (≥90%) — вердикт **ЧИСТЫЙ IP**; если расходятся — **ГРЯЗНЫЙ IP** (например, половина баз видит US, часть RU).

**check-services** — легенда значений:

- `US / RU / ..` — точная страна по официальному API сервиса
- `Yes / No` — доступность или поддержка (YouTube Premium, Gemini и т.п.)
- `OK / HTTP-код` — эвристика по доступности сайта
- `Возможна защита/блок (HTTP 403/404/451)` — обычно анти-бот защита датацентровых IP, не обязательно геоблок

---

## Лицензия

MIT — можно использовать, копировать и изменять свободно.

> Этот репозиторий и все скрипты в нём созданы ИИ-агентами на платформе opencode.
