# Server Utils

Набор bash-скриптов для проверки VPS-сервера: геолокация IP и то, как его видят зарубежные сервисы.

## Скрипты

| Скрипт | Назначение |
|---|---|
| `setup.sh` | Установка `ipregion.sh` (оригинальный скрипт vernette/ipregion) |
| `check-location.sh` | Геолокация IP по 18 GeoIP-базам, подсчёт голосов, вердикт «ЧИСТЫЙ/ГРЯЗНЫЙ» |
| `check-services.sh` | Как IP видят Google, топ ИИ и сервисы, ушедшие из РФ |

## Требования

- Linux VPS с `curl` и `jq`: `apt install -y curl jq`

## Запуск (без установки)

Установка ipregion:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Jzen86/server/main/setup.sh)
```

Геолокация IP:

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

> Этот репозиторий и все скрипты в нём созданы с помощью ИИ — [opencode](https://opencode.ai).
