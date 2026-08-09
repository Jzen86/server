#!/usr/bin/env bash
# ============================================================================
# check-services.sh — как ваш IP видят сервисы:
#   • Google-экосистема  (Google, YouTube, YouTube Premium, Gemini, captcha)
#   • Топ ИИ             (ChatGPT, Claude, Gemini, Perplexity, DeepSeek,
#                         Copilot, Grok)
#   • Ушедшие из РФ      (Netflix, Spotify, Steam, Reddit, Twitch, Disney+,
#                         Apple, Tiktok, Prime, HBO Max, Paramount+, Peacock,
#                         FuboTV, Tubi, Crunchyroll, DAZN)
#   • Креативные ИИ      (Suno, Midjourney, Leonardo, Hugging Face, Stability)
#
# Запуск:    bash check-services.sh      (или ./check-services.sh)
# Зависимости: curl, jq
#
# Легенда значений:
#   страна (US/RU/..)      — точная проверка по официальному API сервиса
#   Yes / No               — доступность/поддержка
#   OK / HTTP-код          — эвристика по доступности сайта или API
#   «Возможен геоблок»     — сайт отдаёт 403/404/406/451 для вашего IP
# ============================================================================

set -Eeuo pipefail

UA="Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
TIMEOUT=6

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; WHITE=$'\033[1;37m'; GRAY=$'\033[0;90m'; NC=$'\033[0m'

# --- ключи/токены (публичные, из проекта vernette/ipregion) ----------------
SPOTIFY_API_KEY="142b583129b2df829de3656f9eb484e6"
SPOTIFY_CLIENT_ID="9a8d2f0ce77a4e248bb71fefcb557637"
NETFLIX_API_KEY="YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm"
TWITCH_CLIENT_ID="kimne78kx3ncx6brgo4mv6wki5h1ko"
CHATGPT_STATSIG_API_KEY="client-zUdXdSTygXJdzoE0sWTkP8GKTVsUMF2IRM7ShVO2JAG"
REDDIT_BASIC_ACCESS_TOKEN="b2hYcG9xclpZdWIxa2c6"
YOUTUBE_SOCS_COOKIE="CAISNQgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjUwNzMwLjA1X3AwGgJlbiACGgYIgPC_xAY"
DISNEY_PLUS_API_KEY="ZGlzbmV5JmFuZHJvaWQmMS4wLjA.bkeb0m230uUhv8qrAXuNu39tbE_mD5EEhM_NAcohjyA"
DISNEY_PLUS_JSON_BODY='{"query":"\n     mutation registerDevice($registerDevice: RegisterDeviceInput!) {\n       registerDevice(registerDevice: $registerDevice) {\n         __typename\n       }\n     }\n     ","variables":{"registerDevice":{"applicationRuntime":"android","attributes":{"operatingSystem":"Android","operatingSystemVersion":"13"},"deviceFamily":"android","deviceLanguage":"en","deviceProfile":"phone","devicePlatformId":"android"}},"operationName":"registerDevice"}'

GEMINI_SUPPORTED=(AL DZ AS AD AO AI AQ AG AR AM AW AU AT AZ BS BH BD BB BE BZ BJ BM BT BO BA BW BR IO VG BN BG BF BI CV KH CM CA BQ KY CF TD CL CX CC CO KM CK CR CI HR CW CZ CD DK DJ DM DO EC EG SV GQ ER EE SZ ET FK FO FJ FI FR GF GA GM GE DE GH GI GR GL GD GU GT GG GN GW GY HT HM HN HU IS IN ID IQ IE IM IL IT JM JP JE JO JZ KZ KE KI XK KW KG LA LV LB LS LR LY LI LT LU MG MW MY MV ML MT MH MR MU MX FM MD MC MN ME MS MA MZ NA NR NP NL NC NZ NI NE NG NU NF MK MP NO OM PK PW PS PA PG PY PE PH PN PL PT PR QA CY CG RO RW RE BL SH KN LC PM VC WS SM ST SA SN RS SC SL SG SK SI SB SO ZA GS KR SS ES LK SD SR SE CH TW TJ TZ TH TL TG TK TO TT TN TM TC TV TR UG UA AE GB US UM UY VI UZ VU VA VE VN WF EH YE ZM ZW AX)

EXTERNAL_IP=""
REQ_CODE="000"

declare -a RESULTS

# --- helpers ---------------------------------------------------------------
req() { # req <url> [curl args...] -> body, ставит REQ_CODE
  local url="$1"; shift
  local tmp
  tmp=$(curl -sL --compressed --max-time "$TIMEOUT" -A "$UA" -w '\n%{http_code}' "$@" "$url" 2>/dev/null || true)
  REQ_CODE=$(tail -n1 <<<"$tmp")
  [[ -z "$REQ_CODE" ]] && REQ_CODE="000"
  head -n -1 <<<"$tmp"
}

json_get() {
  local json="$1" filter="$2"
  if [[ -z "$json" ]]; then echo ""; return; fi
  jq -r "$filter" 2>/dev/null <<<"$json" || true
}

norm() {
  local v="${1//$'\n'/}"
  v="${v//$'\r'/}"
  v="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$v")"
  [[ -z "$v" || "$v" == "null" ]] && echo "N/A" || echo "$v"
}

grepq() { grep "$@" || true; }

status_of() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -L --max-time "$TIMEOUT" -A "$UA" "$1" 2>/dev/null)
  [[ -n "$code" ]] && echo "$code" || echo "000"
}

status_label() {
  local code="$1"
  case "$code" in
    200|201|202|204) echo "OK (HTTP $code)" ;;
    301|302|303|307|308) echo "OK (redirect $code)" ;;
    401) echo "Доступен (HTTP 401 — нужен ключ)" ;;
    403|404|405|406|451) echo "Возможен геоблок (HTTP $code)" ;;
    429) echo "Rate-limit (HTTP 429)" ;;
    000) echo "Нет ответа" ;;
    *) echo "HTTP $code" ;;
  esac
}

add_result() {
  local group="$1" name="$2"
  local value
  value=$(norm "$3")
  if [[ "$value" =~ ^[a-z]{2}$ ]]; then
    value="${value^^}"
  fi
  RESULTS+=("$group|$name|$value")
}

get_external_ip() {
  local ip u
  for u in "https://api.ipify.org" "https://ifconfig.me/ip" "https://ident.me"; do
    ip=$(req "$u" | tr -d '[:space:]')
    if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
      EXTERNAL_IP="$ip"
      return 0
    fi
  done
  return 1
}

# ============================================================================
# ГОOGLE-ЭКОСИСТЕМА
# ============================================================================
check_google() {
  local body
  body=$(req "https://accounts.google.com/v3/signin/identifier?flowName=GlifSetupAndroid")
  add_result "google" "Google" "$(grepq -oP 'name="region" value="\K[^"]*' <<<"$body" | head -n1)"
}

check_youtube() {
  local body
  body=$(req "https://www.youtube.com/sw.js_data")
  add_result "google" "YouTube" "$(json_get "$(tail -n +3 <<<"$body")" ".[0][2][0][0][1]")"
}

check_youtube_premium() {
  local body
  body=$(req "https://www.youtube.com/premium" -H "Cookie: SOCS=$YOUTUBE_SOCS_COOKIE" -H "Accept-Language: en-US,en;q=0.9")
  if [[ -z "$body" ]]; then add_result "google" "YouTube Premium" "N/A"; return; fi
  if grep -ioq "youtube premium is not available in your country" <<<"$body"; then
    add_result "google" "YouTube Premium" "No"
  else
    add_result "google" "YouTube Premium" "Yes"
  fi
}

check_gemini() {
  local cc body
  body=$(req "https://accounts.google.com/v3/signin/identifier?flowName=GlifSetupAndroid")
  cc=$(grepq -oP 'name="region" value="\K[^"]*' <<<"$body" | head -n1)
  cc="${cc^^}"
  if [[ -z "$cc" ]]; then add_result "google" "Gemini" "N/A"; return; fi
  if printf "%s\n" "${GEMINI_SUPPORTED[@]}" | grep -Fxq "$cc"; then
    add_result "google" "Gemini" "Yes"
  else
    add_result "google" "Gemini" "No"
  fi
}

check_google_captcha() {
  local body
  body=$(req "https://www.google.com/search?q=cats" -H "Accept-Language: en-US,en;q=0.9")
  if [[ -z "$body" ]]; then add_result "google" "Google Captcha" "N/A"; return; fi
  if grep -qiE "unusual traffic from|is blocked|unaddressed abuse" <<<"$body"; then
    add_result "google" "Google Captcha" "Yes"
  else
    add_result "google" "Google Captcha" "No"
  fi
}

# ============================================================================
# ТОП ИИ
# ============================================================================
check_chatgpt() {
  local body
  body=$(req "https://ab.chatgpt.com/v1/initialize" -X POST -H "Statsig-Api-Key: $CHATGPT_STATSIG_API_KEY")
  add_result "ai" "ChatGPT" "$(json_get "$body" ".derived_fields.country")"
}

check_claude() {
  add_result "ai" "Claude (claude.ai)" "$(status_label "$(status_of "https://claude.ai/")")"
}

check_perplexity() {
  add_result "ai" "Perplexity" "$(status_label "$(status_of "https://www.perplexity.ai/")")"
}

check_deepseek() {
  add_result "ai" "DeepSeek" "$(status_label "$(status_of "https://api.deepseek.com/")")"
}

check_copilot() {
  add_result "ai" "Copilot" "$(status_label "$(status_of "https://copilot.microsoft.com/")")"
}

check_grok() {
  add_result "ai" "Grok (xAI)" "$(status_label "$(status_of "https://grok.com/")")"
}

# ============================================================================
# УШЕДШИЕ ИЗ РФ
# ============================================================================
check_netflix() {
  local body cc
  body=$(req "https://api.fast.com/netflix/speedtest/v2?https=true&token=$NETFLIX_API_KEY&urlCount=1")
  cc=$(json_get "$body" ".client.location.country")
  if [[ -n "$cc" ]]; then
    add_result "leftrf" "Netflix" "$cc"
  elif [[ -z "$body" ]]; then
    add_result "leftrf" "Netflix" "N/A"
  else
    add_result "leftrf" "Netflix" "$body"
  fi
}

check_spotify() {
  local body
  body=$(req "https://spclient.wg.spotify.com/signup/public/v1/account/?validate=1&key=$SPOTIFY_API_KEY" -H "X-Client-Id: $SPOTIFY_CLIENT_ID")
  add_result "leftrf" "Spotify" "$(json_get "$body" ".country")"
}

check_spotify_signup() {
  local body status launched
  body=$(req "https://spclient.wg.spotify.com/signup/public/v1/account/?validate=1&key=$SPOTIFY_API_KEY" -H "X-Client-Id: $SPOTIFY_CLIENT_ID")
  status=$(json_get "$body" ".status")
  launched=$(json_get "$body" ".is_country_launched")
  if [[ "$status" == "120" || "$status" == "320" || "$launched" == "false" ]]; then
    add_result "leftrf" "Spotify Signup" "No"
  else
    add_result "leftrf" "Spotify Signup" "Yes"
  fi
}

check_steam() {
  local body
  body=$(req "https://store.steampowered.com" -I)
  add_result "leftrf" "Steam" "$(grepq -oP 'steamCountry=\K[^%;]*' <<<"$body" | head -n1)"
}

check_reddit() {
  local body atoken
  body=$(req "https://www.reddit.com/auth/v2/oauth/access-token/loid" -X POST \
    -A "Reddit/Version 2025.29.0/Build 2529021/Android 13" \
    -H "Authorization: Basic $REDDIT_BASIC_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    --data '{"scopes":["email"]}')
  atoken=$(json_get "$body" ".access_token")
  if [[ -z "$atoken" ]]; then
    add_result "leftrf" "Reddit" "N/A"
    return
  fi
  body=$(req "https://gql-fed.reddit.com" -X POST \
    -A "Reddit/Version 2025.29.0/Build 2529021/Android 13" \
    -H "Authorization: Bearer $atoken" \
    -H "Content-Type: application/json" \
    --data '{"operationName":"UserLocation","variables":{},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"f07de258c54537e24d7856080f662c1b1268210251e5789c8c08f20d76cc8ab2"}}}')
  add_result "leftrf" "Reddit" "$(json_get "$body" ".data.userLocation.countryCode")"
}

check_reddit_guest() {
  local body code
  body=$(req "https://www.reddit.com")
  code="$REQ_CODE"
  if [[ "$code" =~ ^[45] ]]; then
    add_result "leftrf" "Reddit (гостевой доступ)" "No"
    return
  fi
  if [[ -z "$body" ]]; then
    add_result "leftrf" "Reddit (гостевой доступ)" "N/A"
    return
  fi
  if grep -qi "Denied" <<<"$body"; then
    add_result "leftrf" "Reddit (гостевой доступ)" "No"
  else
    add_result "leftrf" "Reddit (гостевой доступ)" "Yes"
  fi
}

check_twitch() {
  local body
  body=$(req "https://gql.twitch.tv/gql" -X POST -H "Client-Id: $TWITCH_CLIENT_ID" \
    -H "Content-Type: application/json" \
    --data '[{"operationName":"VerifyEmail_CurrentUser","variables":{},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"f9e7dcdf7e99c314c82d8f7f725fab5f99d1df3d7359b53c9ae122deec590198"}}}]')
  add_result "leftrf" "Twitch" "$(json_get "$body" ".[0].data.requestInfo.countryCode")"
}

check_disney() {
  local body
  body=$(req "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql" -X POST \
    -H "Authorization: Bearer $DISNEY_PLUS_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$DISNEY_PLUS_JSON_BODY")
  add_result "leftrf" "Disney+" "$(json_get "$body" ".extensions.sdk.session.location.countryCode")"
}

check_disney_access() {
  local body errs loc
  body=$(req "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql" -X POST \
    -H "Authorization: Bearer $DISNEY_PLUS_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$DISNEY_PLUS_JSON_BODY")
  errs=$(json_get "$body" ".errors | length")
  loc=$(json_get "$body" ".extensions.sdk.session.inSupportedLocation")
  if [[ "$errs" == "0" && "$loc" == "true" ]]; then
    add_result "leftrf" "Disney+ (доступ)" "Yes"
  else
    add_result "leftrf" "Disney+ (доступ)" "No"
  fi
}

check_apple() {
  add_result "leftrf" "Apple" "$(req "https://gspe1-ssl.ls.apple.com/pep/gcc")"
}

check_tiktok() {
  local body
  body=$(req "https://www.tiktok.com/api/v1/web-cookie-privacy/config?appId=1988")
  add_result "leftrf" "Tiktok" "$(json_get "$body" ".body.appProps.region")"
}

check_prime() {
  local body blocked region
  body=$(req "https://www.primevideo.com")
  if [[ -z "$body" ]]; then add_result "leftrf" "Prime Video" "N/A"; return; fi
  blocked=$(grepq -i "isServiceRestricted" <<<"$body")
  region=$(grepq -oP '"currentTerritory":"\K[^"]+' <<<"$body" | head -n1)
  if [[ -z "$blocked" && -z "$region" ]]; then add_result "leftrf" "Prime Video" "Failed (PAGE ERROR)"; return; fi
  if [[ -n "$blocked" ]]; then add_result "leftrf" "Prime Video" "No (Service Not Available)"; return; fi
  if [[ -n "$region" ]]; then add_result "leftrf" "Prime Video" "Yes (Region: $region)"; return; fi
  add_result "leftrf" "Prime Video" "Failed (Unknown Region)"
}

check_hbo() {
  local body region
  body=$(req "https://www.max.com/" -i)
  if [[ -z "$body" ]]; then add_result "leftrf" "HBO Max" "N/A"; return; fi
  region=$(grepq -oP 'countryCode=\K[A-Z]{2}' <<<"$body" | head -n1)
  if [[ -z "$region" ]]; then add_result "leftrf" "HBO Max" "Failed (Country Code Not Found)"; return; fi
  add_result "leftrf" "HBO Max" "Yes (Region: $region)"
}

check_paramount() {
  local url code region
  url=$(curl -s -o /dev/null -L -w '%{url_effective}' --max-time "$TIMEOUT" -A "$UA" "https://www.paramountplus.com/" 2>/dev/null || true)
  code=$(curl -s -o /dev/null -L -w '%{http_code}' --max-time "$TIMEOUT" -A "$UA" "https://www.paramountplus.com/" 2>/dev/null || true)
  if [[ -z "$url" ]]; then add_result "leftrf" "Paramount+" "N/A"; return; fi
  region=$(awk -F'/' '{print $4}' <<<"$url" | tr 'a-z' 'A-Z')
  if [[ "$region" == "INTL" ]]; then add_result "leftrf" "Paramount+" "No"; return; fi
  if [[ "$code" == "200" ]]; then add_result "leftrf" "Paramount+" "Yes (Region: ${region:-US})"; return; fi
  add_result "leftrf" "Paramount+" "Failed (Error: $code)"
}

check_peacock() {
  local url code
  url=$(curl -s -o /dev/null -L -w '%{url_effective}' --max-time "$TIMEOUT" -A "$UA" "https://www.peacocktv.com/" 2>/dev/null || true)
  code=$(curl -s -o /dev/null -L -w '%{http_code}' --max-time "$TIMEOUT" -A "$UA" "https://www.peacocktv.com/" 2>/dev/null || true)
  if [[ -z "$url" ]]; then add_result "leftrf" "Peacock" "N/A"; return; fi
  if grep -qi 'unavailable' <<<"$url"; then add_result "leftrf" "Peacock" "No"; return; fi
  if [[ "$code" == "200" ]]; then add_result "leftrf" "Peacock" "Yes"; return; fi
  add_result "leftrf" "Peacock" "Failed (Error: $code)"
}

check_fubo() {
  local body cc
  body=$(req "https://api.fubo.tv/v3/location" -H "Origin: https://www.fubo.tv" -H "Referer: https://www.fubo.tv/")
  if [[ -z "$body" ]]; then add_result "leftrf" "FuboTV" "N/A"; return; fi
  if grep -qi 'NO_SERVICE_IN_COUNTRY' <<<"$body" || grep -q '"network_allowed":false' <<<"$body"; then
    add_result "leftrf" "FuboTV" "No"
    return
  fi
  if grep -q '"network_allowed":true' <<<"$body"; then
    cc=$(grepq -oP '"country_code2":"\K[^"]+' <<<"$body")
    add_result "leftrf" "FuboTV" "Yes (Region: $cc)"
    return
  fi
  add_result "leftrf" "FuboTV" "Failed (Unknown)"
}

check_tubi() {
  local body blocked ok
  body=$(req "https://tubitv.com/home")
  if [[ -z "$body" ]]; then add_result "leftrf" "Tubi" "N/A"; return; fi
  blocked=$(grepq -i "not currently available in your area" <<<"$body")
  ok=$(grepq -i "manifest" <<<"$body")
  if [[ -z "$blocked" && -z "$ok" ]]; then add_result "leftrf" "Tubi" "Failed (PAGE ERROR)"; return; fi
  if [[ -n "$blocked" ]]; then add_result "leftrf" "Tubi" "No"; return; fi
  if [[ -n "$ok" ]]; then add_result "leftrf" "Tubi" "Yes"; return; fi
  add_result "leftrf" "Tubi" "Failed (Unknown)"
}

check_crunchyroll() {
  local body region
  body=$(req "https://c.evidon.com/geo/country.js")
  if [[ -z "$body" ]]; then add_result "leftrf" "Crunchyroll" "N/A"; return; fi
  region=$(grepq -oP "'code':'\K[a-z]{2}'" <<<"$body" | head -n1)
  if [[ -z "$region" ]]; then add_result "leftrf" "Crunchyroll" "No"; return; fi
  add_result "leftrf" "Crunchyroll" "Yes (Region: ${region^^})"
}

check_dazn() {
  local body allowed region
  body=$(req "https://startup.core.indazn.com/misl/v5/Startup" -X POST \
    -H "Content-Type: application/json" \
    --data '{"Version":"2","LandingPageKey":"generic","Languages":"en-US","Platform":"web","Manufacturer":"","PromoCode":"","PlatformAttributes":{}}')
  if [[ -z "$body" ]]; then add_result "leftrf" "DAZN" "N/A"; return; fi
  if grep -qi "Security policy has been breached" <<<"$body"; then add_result "leftrf" "DAZN" "No (IP Banned)"; return; fi
  allowed=$(grepq -oP '"isAllowed"\s{0,}:\s{0,}\K(false|true)' <<<"$body")
  region=$(grepq -oP '"GeolocatedCountry"\s{0,}:\s{0,}"\K[^"]+' <<<"$body" | tr 'a-z' 'A-Z')
  if [[ "$allowed" == "true" ]]; then add_result "leftrf" "DAZN" "Yes (Region: ${region:-N/A})"; return; fi
  if [[ "$allowed" == "false" ]]; then add_result "leftrf" "DAZN" "No"; return; fi
  add_result "leftrf" "DAZN" "Failed (Error: ${allowed:-Unknown})"
}

# ============================================================================
# КРЕАТИВНЫЕ ИИ
# ============================================================================
check_suno() {
  add_result "creative" "Suno" "$(status_label "$(status_of "https://suno.com/")")"
}

check_midjourney() {
  add_result "creative" "Midjourney" "$(status_label "$(status_of "https://www.midjourney.com/")")"
}

check_leonardo() {
  add_result "creative" "Leonardo" "$(status_label "$(status_of "https://leonardo.ai/")")"
}

check_huggingface() {
  add_result "creative" "Hugging Face" "$(status_label "$(status_of "https://huggingface.co/api/models?limit=1")")"
}

check_stability() {
  add_result "creative" "Stability AI" "$(status_label "$(status_of "https://platform.stability.ai/")")"
}

# ============================================================================
# ВЫВОД
# ============================================================================
fmt_value() {
  local v="$1"
  case "$v" in
    N/A)                       echo -e "${GRAY}N/A${NC}" ;;
    *"Rate-limit"*)            echo -e "${YELLOW}${v}${NC}" ;;
    Yes*)                      echo -e "${GREEN}${v}${NC}" ;;
    No*)                       echo -e "${RED}${v}${NC}" ;;
    *"(Region:"*)              echo -e "${GREEN}${v}${NC}" ;;
    *"геоблок"*)               echo -e "${RED}${v}${NC}" ;;
    *"Failed"*)                echo -e "${YELLOW}${v}${NC}" ;;
    *"OK"*)                    echo -e "${GREEN}${v}${NC}" ;;
    *"Доступен"*)              echo -e "${GREEN}${v}${NC}" ;;
    HTTP\ [45][0-9][0-9])      echo -e "${RED}${v}${NC}" ;;
    *)                         echo -e "${WHITE}${v}${NC}" ;;
  esac
}

print_section() {
  local title="$1" prefix="$2"
  echo ""
  echo -e "${CYAN}── ${title} ──${NC}"
  local row group name value
  for row in "${RESULTS[@]}"; do
    IFS='|' read -r group name value <<<"$row"
    [[ "$group" == "$prefix" ]] || continue
    printf "  %-26s %s\n" "$name" "$(fmt_value "$value")"
  done
}

main() {
  echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
  echo -e "${WHITE}check-services — как твой IP видят сервисы${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"

  if ! command -v curl >/dev/null 2>&1; then echo -e "${RED}Нужен curl${NC}"; exit 1; fi
  if ! command -v jq >/dev/null 2>&1; then echo -e "${RED}Нужен jq (apt install jq)${NC}"; exit 1; fi

  if get_external_ip; then
    echo -e "  ${WHITE}IP:${NC} ${GREEN}${EXTERNAL_IP%.*.*}.*.*${NC}"
  else
    echo -e "  ${GRAY}Не удалось получить внешний IP${NC}"
  fi

  check_google
  check_youtube
  check_youtube_premium
  check_gemini
  check_google_captcha

  check_chatgpt
  check_claude
  check_perplexity
  check_deepseek
  check_copilot
  check_grok

  check_netflix
  check_spotify
  check_spotify_signup
  check_steam
  check_reddit
  check_reddit_guest
  check_twitch
  check_disney
  check_disney_access
  check_apple
  check_tiktok
  check_prime
  check_hbo
  check_paramount
  check_peacock
  check_fubo
  check_tubi
  check_crunchyroll
  check_dazn

  check_suno
  check_midjourney
  check_leonardo
  check_huggingface
  check_stability

  print_section "Google-экосистема" "google"
  print_section "Топ ИИ" "ai"
  print_section "Ушедшие из РФ" "leftrf"
  print_section "Креативные ИИ" "creative"

  echo -e "\n${GRAY}— страна (US/RU/..) = точная проверка по API сервиса; OK/HTTP-код = эвристика по доступности; «Возможен геоблок» = 403/404/451 для вашего IP${NC}"
}

main "$@"
