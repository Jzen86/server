#!/usr/bin/env bash

USER_AGENT="Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
GEMINI_REGIONS_URL="https://ai.google.dev/gemini-api/docs/available-regions.md.txt"

do_curl() {
    curl -s --compressed --location --max-time 5 -A "$USER_AGENT" "$@"
}

echo "=== Проверка доступности Gemini для текущего IP ==="

google_response=$(do_curl "https://accounts.google.com/v3/signin/identifier?flowName=GlifSetupAndroid")
country_code=$(grep -oP 'name="region" value="\K[^"]*' <<< "$google_response")

if [[ -z "$country_code" ]]; then
    echo "Ошибка: не удалось определить регион через Google."
    exit 1
fi

country_json=$(do_curl "https://www.apicountries.com/alpha/${country_code}")
country_name=$(jq -r '.name // empty' <<< "$country_json")

if [[ -z "$country_name" ]]; then
    echo "Ошибка: не удалось получить название страны по коду $country_code."
    exit 1
fi

regions_md=$(do_curl "$GEMINI_REGIONS_URL")

if grep -qi "^- ${country_name}$" <<< "$regions_md"; then
    echo -e "Статус Gemini: \033[1;32mДоступно (Yes)\033[00m"
else
    echo -e "Статус Gemini: \033[1;31mНедоступно (No)\033[0m"
    echo -e "Причина: Google видит твою локацию как \033[1;33m$country_name\033[0m ($country_code), а её нет в списке поддерживаемых."
fi
