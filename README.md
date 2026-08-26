# Server Utils

Набор скриптов для проверки VPS-сервера: геолокация IP, как его видят сервисы, и проверка на блокировки в России.

## Скрипты

| Скрипт | Назначение |
|---|---|
| server-check.sh | Меню: запуск check-location.sh, check-services.sh или обоих по очереди |
| check-location.sh | Геолокация IP по 18 GeoIP-базам, подсчёт голосов, вердикт ЧИСТЫЙ/ГРЯЗНЫЙ |
| check-services.sh | Как IP видят Google, топ ИИ и сервисы, ушедшие из РФ |
| check-ip.py | Проверка IP/домена по 18 спискам блокировок РКН и CDN-провайдеров |

## Требования

- Linux VPS с curl и jq: apt install -y curl jq
- check-ip.py требует Python 3.6+ (стандартная библиотека, без pip install)

## Запуск (без установки)

Меню всех проверок (server-check.sh):

```bash
bash <(curl -sL https://raw.githubusercontent.com/Jzen86/server/main/server-check.sh)
```

При выборе 1 запустится check-location.sh, при выборе 2 check-services.sh, при выборе 3 оба по очереди, 0 выход.

Геолокация IP напрямую:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Jzen86/server/main/check-location.sh)
```

Проверка сервисов:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Jzen86/server/main/check-services.sh)
```

Проверка на блокировки в России:

```bash
python3 <(curl -sL https://raw.githubusercontent.com/Jzen86/server/main/check-ip.py)
```

При запуске скрипт покажет меню:
- 1 проверить внешний IP этого сервера (авто-определение)
- 2 ввести другой IP или домен вручную

## Как читать вывод

check-location 18 GeoIP-баз голосуют за страну IP. Если базы единодушны (>=90%) вердикт ЧИСТЫЙ IP если расходятся ГРЯЗНЫЙ IP.

check-services легенда значений:
- US / RU / .. точная страна по официальному API сервиса
- Yes / No доступность или поддержка
- OK / HTTP-код эвристика по доступности сайта
- Возможна защита/блок (HTTP 403/404/451) обычно анти-бот защита датацентровых IP

check-ip.py проверяет IP по 18 источникам:
- antifilter.download IP-адреса и подсети из реестра РКН (обновление раз в 30мин)
- cdn-ip-ranges подсети CDN-провайдеров: Cloudflare, AWS, Hetzner, OVH, DigitalOcean, Akamai, Fastly, GCore, Vercel и др. (обновление раз в 12ч)
- Домены из реестра РКН

Вердикты:
- ЧИСТ IP не найден ни в одном списке
- ЗАБЛОКИРОВАН: реестр РКН IP/домен в публичном реестре Роскомнадзора
- ЗАБЛОКИРОВАН: CDN-блок подсеть CDN в блок-листе (трафик режется на 16-20 КБ)
- ЗАБЛОКИРОВАН: реестр РКН + CDN-блок и то и другое

Блокировки YouTube, Discord и др. могут не определяться часть ограничений непубличная и не попадает в реестры.

---

## Лицензия

MIT можно использовать копировать и изменять свободно.

Этот репозиторий и все скрипты в нём созданы ИИ-агентами на платформе opencode (https://opencode.ai).
