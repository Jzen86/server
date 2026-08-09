#!/usr/bin/env bash
# ============================================================================
# check-location.sh — геолокация внешнего IP по 18 независимым GeoIP-базам
# с итоговым подсчётом голосов и вердиктом «чистый / грязный».
#
#   ЧИСТЫЙ   — >= 90% успешных баз называют одну и ту же страну
#   ГРЯЗНЫЙ  — базы расходятся (часть говорит одно, часть другое)
#
# Запуск:   bash check-location.sh            (или ./check-location.sh)
# Зависимости: curl, jq
# ============================================================================

set -Eeuo pipefail

UA="Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
TIMEOUT=6

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; WHITE=$'\033[1;37m'; GRAY=$'\033[0;90m'; NC=$'\033[0m'

EXTERNAL_IP=""
REGISTERED_COUNTRY=""
ASN_INFO=""
REQ_CODE="000"

declare -a RESULTS
declare -A VOTES

# --- helpers ---------------------------------------------------------------
req() { # req <url> [curl args...] -> body, ставит REQ_CODE
  local url="$1"; shift
  local tmp
  tmp=$(curl -sL --compressed --max-time "$TIMEOUT" -A "$UA" -w '\n%{http_code}' "$@" "$url" 2>/dev/null || true)
  REQ_CODE=$(tail -n1 <<<"$tmp")
  [[ -z "$REQ_CODE" ]] && REQ_CODE="000"
  head -n -1 <<<"$tmp"
}

json_get() { # json_get <json> <jq-filter>
  local json="$1" filter="$2"
  if [[ -z "$json" ]]; then echo ""; return; fi
  jq -r "$filter" 2>/dev/null <<<"$json" || true
}

norm() {
  local v="${1//$'\n'/}"
  v="${v//[[:space:]]/}"
  [[ -z "$v" || "$v" == "null" ]] && echo "N/A" || echo "$v"
}

add_result() {
  local name="$1" value
  value=$(norm "$2")
  if [[ "$value" =~ ^[A-Za-z]{2}$ ]]; then
    value="${value^^}"
  fi
  RESULTS+=("$name|$value")
  VOTES["$value"]=$(( ${VOTES["$value"]:-0} + 1 ))
}

# --- внешний IP ------------------------------------------------------------
get_external_ip() {
  local ip u
  for u in "https://api.ipify.org" "https://ifconfig.me/ip" "https://ident.me" "https://icanhazip.com"; do
    ip=$(req "$u" | tr -d '[:space:]')
    if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
      EXTERNAL_IP="$ip"
      return 0
    fi
  done
  return 1
}

# --- мета (MaxMind) --------------------------------------------------------
get_meta() {
  local json asn asn_name
  json=$(req "https://geoip.maxmind.com/geoip/v2.1/city/me" -H "Referer: https://www.maxmind.com")
  REGISTERED_COUNTRY=$(norm "$(json_get "$json" ".registered_country.names.en")")
  asn=$(json_get "$json" ".traits.autonomous_system_number")
  asn_name=$(json_get "$json" ".traits.autonomous_system_organization")
  [[ "$asn" =~ ^[0-9]+$ ]] && ASN_INFO="AS${asn} ${asn_name}"
}

# --- чекеры ----------------------------------------------------------------
check_maxmind() {
  local body
  body=$(req "https://geoip.maxmind.com/geoip/v2.1/city/me" -H "Referer: https://www.maxmind.com")
  add_result "maxmind.com" "$(json_get "$body" ".country.iso_code")"
}

check_ipinfo() {
  add_result "ipinfo.io" "$(json_get "$(req "https://ipinfo.io/json")" ".country")"
}

check_cloudflare() {
  add_result "cloudflare.com" "$(json_get "$(req "https://speed.cloudflare.com/meta" -H "Referer: https://speed.cloudflare.com")" ".country")"
}

check_ipregistry() {
  add_result "ipregistry.co" "$(json_get "$(req "https://api.ipregistry.co/${EXTERNAL_IP}?hostname=true&key=sb69ksjcajfs4c")" ".location.country.code")"
}

check_ipapi_co() {
  local body
  body=$(req "https://ipapi.co/${EXTERNAL_IP}/json")
  if [[ "$REQ_CODE" == "429" ]]; then add_result "ipapi.co" "Rate-limit"; return; fi
  add_result "ipapi.co" "$(json_get "$body" ".country")"
}

check_ifconfig_co() {
  add_result "ifconfig.co" "$(req "https://ifconfig.co/country-iso?ip=${EXTERNAL_IP}")"
}

check_ip2location() {
  add_result "ip2location.io" "$(json_get "$(req "https://api.ip2location.io/?ip=${EXTERNAL_IP}")" ".country_code")"
}

check_iplocation() {
  add_result "iplocation.com" "$(json_get "$(req "https://iplocation.com" --data "ip=${EXTERNAL_IP}")" ".country_code")"
}

check_country_is() {
  add_result "country.is" "$(json_get "$(req "https://api.country.is/${EXTERNAL_IP}")" ".country")"
}

check_geoapify() {
  add_result "geoapify.com" "$(json_get "$(req "https://api.geoapify.com/v1/ipinfo?&ip=${EXTERNAL_IP}&apiKey=b8568cb9afc64fad861a69edbddb2658")" ".country.iso_code")"
}

check_geojs() {
  add_result "geojs.io" "$(json_get "$(req "https://get.geojs.io/v1/ip/country.json?ip=${EXTERNAL_IP}")" ".[0].country")"
}

check_ipapi_is() {
  add_result "ipapi.is" "$(json_get "$(req "https://api.ipapi.is/?q=${EXTERNAL_IP}")" ".location.country_code")"
}

check_ipbase() {
  add_result "ipbase.com" "$(json_get "$(req "https://api.ipbase.com/v2/info?ip=${EXTERNAL_IP}")" ".data.location.country.alpha2")"
}

check_ipquery() {
  add_result "ipquery.io" "$(json_get "$(req "https://api.ipquery.io/${EXTERNAL_IP}")" ".location.country_code")"
}

check_ipwho() {
  add_result "ipwho.is" "$(json_get "$(req "https://ipwho.is/${EXTERNAL_IP}")" ".country_code")"
}

check_ipapi_com() {
  add_result "ip-api.com" "$(json_get "$(req "https://demo.ip-api.com/json/${EXTERNAL_IP}?fields=countryCode")" ".countryCode")"
}

check_freeipapi() {
  add_result "freeipapi.com" "$(json_get "$(req "https://freeipapi.com/api/json/${EXTERNAL_IP}")" ".countryCode")"
}

check_ipwhois() {
  add_result "ipwhois.app" "$(json_get "$(req "https://ipwhois.app/json/${EXTERNAL_IP}")" ".data.country_code")"
}

ALL_CHECKS="check_maxmind check_ipinfo check_cloudflare check_ipregistry check_ipapi_co check_ifconfig_co check_ip2location check_iplocation check_country_is check_geoapify check_geojs check_ipapi_is check_ipbase check_ipquery check_ipwho check_ipapi_com check_freeipapi check_ipwhois"

mask_ip() {
  echo "${EXTERNAL_IP%.*.*}.*.*"
}

print_verdict() {
  local best="" bestn=0 total=0 k n pct
  for k in "${!VOTES[@]}"; do
    if [[ "$k" =~ ^[A-Z]{2}$ ]]; then
      n=${VOTES[$k]}
      total=$((total + n))
      if (( n > bestn )); then bestn=$n; best=$k; fi
    fi
  done

  if (( total == 0 )); then
    echo -e "${YELLOW}Вердикт: нет данных (все базы не ответили)${NC}"
    return
  fi

  pct=$(( bestn * 100 / total ))

  echo -e "\n${CYAN}Итог по странам:${NC}"
  local line
  while read -r line; do
    [[ -z "$line" ]] && continue
    n=${line%%|*}; k=${line##*|}
    echo -e "  ${WHITE}${k}${NC}: ${n}"
  done < <(for k in "${!VOTES[@]}"; do echo "${VOTES[$k]}|${k}"; done | sort -rn)

  echo ""
  if (( pct >= 90 )); then
    echo -e "  ${GREEN}Вердикт: ЧИСТЫЙ IP — ${bestn}/${total} баз (${pct}%) видят ${WHITE}${best}${NC}${NC}"
  else
    echo -e "  ${RED}Вердикт: ГРЯЗНЫЙ IP — базы расходятся (лидер ${WHITE}${best}${NC}: ${bestn}/${total} = ${pct}%)${NC}"
  fi
  echo -e "  ${GRAY}Большинство баз считают страну: ${WHITE}${best}${NC}"
}

main() {
  echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
  echo -e "${WHITE}check-location — геолокация IP по 18 GeoIP-базам${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"

  if ! command -v curl >/dev/null 2>&1; then echo -e "${RED}Нужен curl${NC}"; exit 1; fi
  if ! command -v jq >/dev/null 2>&1; then echo -e "${RED}Нужен jq (apt install jq)${NC}"; exit 1; fi

  echo -e "${GRAY}Получаю внешний IP...${NC}"
  if ! get_external_ip; then
    echo -e "${RED}Не удалось получить внешний IP${NC}"
    exit 1
  fi

  get_meta

  echo -e "  ${WHITE}IP:${NC}         ${GREEN}$(mask_ip)${NC}"
  [[ -n "$REGISTERED_COUNTRY" && "$REGISTERED_COUNTRY" != "N/A" ]] && echo -e "  ${WHITE}Зарегистрирован:${NC} ${GREEN}${REGISTERED_COUNTRY}${NC}"
  [[ -n "$ASN_INFO" ]] && echo -e "  ${WHITE}ASN:${NC}       ${GREEN}${ASN_INFO}${NC}"
  echo ""

  echo -e "${CYAN}GeoIP базы (18):${NC}"
  local c
  for c in $ALL_CHECKS; do
    "$c"
  done

  local row name value
  for row in "${RESULTS[@]}"; do
    name="${row%%|*}"; value="${row##*|}"
    printf "  %-22s %s\n" "$name" "$(fmt_value "$value")"
  done

  print_verdict
}

fmt_value() {
  local v="$1"
  case "$v" in
    N/A) echo -e "${GRAY}N/A${NC}" ;;
    Rate-limit) echo -e "${YELLOW}Rate-limit${NC}" ;;
    *) echo -e "${GREEN}${v}${NC}" ;;
  esac
}

main "$@"
