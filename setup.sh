#!/usr/bin/env bash
# ============================================================================
# setup.sh — меню для запуска скриптов репозитория server:
#
#   1) Запустить проверку геолокации по IP           -> check-location.sh
#   2) Запустить проверку на доступность сервисов     -> check-services.sh
#   3) Запустить все                                 -> оба по очереди
#   0) Выход/Назад
#
# Запуск:
#   bash setup.sh                          # локальная копия рядом с файлами
#   bash <(curl -sL https://raw.githubusercontent.com/Jzen86/server/main/setup.sh)
#
# Скрипты ищутся в той же папке, что и setup.sh. Если их там нет —
# они скачиваются с GitHub во временный файл и запускаются.
#
# Зависимости: curl (для скачивания), jq (нужен check-скриптам)
# ============================================================================

set -Eeuo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; WHITE=$'\033[1;37m'; GRAY=$'\033[0;90m'; NC=$'\033[0m'

REPO_URL="https://raw.githubusercontent.com/Jzen86/server/main"
SCRIPT_NAMES=("check-location.sh" "check-services.sh")

# --- каталог скрипта -------------------------------------------------------
# Пустой при запуске через bash <(curl ...) — тогда всегда скачиваем.
SCRIPT_DIR=""
if dir="$(dirname "${BASH_SOURCE[0]}")" && [[ -d "$dir" ]]; then
  SCRIPT_DIR="$(cd "$dir" && pwd)"
fi

# --- зависимости ------------------------------------------------------------
check_deps() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  if ((${#missing[@]})); then
    echo -e "${YELLOW}Внимание: не найдены: ${missing[*]}${NC}"
    echo -e "${GRAY}  Установите: apt install -y ${missing[*]}${NC}"
    echo ""
  fi
}

# --- получение скрипта -------------------------------------------------------
# Отдаёт путь к локальной копии, если она есть рядом, иначе скачивает во временный файл.
get_script() {
  local name="$1"
  local local_path="$SCRIPT_DIR/$name"

  if [[ -n "$SCRIPT_DIR" && -f "$local_path" ]]; then
    echo "$local_path"
    return 0
  fi

  local tmp
  tmp=$(mktemp) || return 1
  if ! curl -fsSL --compressed --max-time 30 "$REPO_URL/$name" -o "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo -e "${RED}Не удалось скачать $name с GitHub${NC}" >&2
    return 1
  fi
  echo "$tmp"
}

# --- запуск одного скрипта ----------------------------------------------------
run_script() {
  local name="$1"
  local path rc=0

  if ! path=$(get_script "$name"); then
    return 0
  fi

  echo -e "${CYAN}============================================================${NC}"
  echo -e "${WHITE}  Запуск: ${name}${NC}"
  echo -e "${CYAN}============================================================${NC}"

  bash "$path" || rc=$?

  if [[ "$path" != "$SCRIPT_DIR/$name" ]]; then
    rm -f "$path"
  fi

  if ((rc != 0)); then
    echo -e "${RED}  Скрипт $name завершился с ошибкой (код $rc)${NC}"
  else
    echo -e "${GREEN}  Скрипт $name выполнен.${NC}"
  fi
  echo ""
  return 0
}

# --- меню ---------------------------------------------------------------------
clear_screen() {
  if command -v clear >/dev/null 2>&1; then
    clear
    printf '\033[3J'
  else
    printf '\033[2J\033[3J\033[H'
  fi
}

show_menu() {
  echo -e "${CYAN}============================================================${NC}"
  echo -e "${WHITE}  Проверки VPS-сервера${NC}"
  echo -e "${CYAN}============================================================${NC}"
  echo "  ${WHITE}1${NC}) Запустить проверку геолокации по IP"
  echo "  ${WHITE}2${NC}) Запустить проверку на доступность сервисов"
  echo "  ${WHITE}3${NC}) Запустить все"
  echo "  ${WHITE}0${NC}) Выход/Назад"
  echo ""
}

# Приглашение после проверки: только «0) Назад в меню».
wait_return() {
  while true; do
    echo ""
    echo -e "  ${WHITE}0${NC}) Назад в меню"
    read -r -p "  Ваш выбор: " choice || true
    choice="${choice//$'\r'/}"

    case "$choice" in
      0 | q | Q | exit)
        return 0
        ;;
      "")
        ;;
      *)
        echo -e "${RED}  Неверный выбор: ${choice}${NC}"
        ;;
    esac
  done
}

main() {
  check_deps

  while true; do
    clear_screen
    show_menu
    read -r -p "  Ваш выбор: " choice || true
    choice="${choice//$'\r'/}"

    case "$choice" in
      1)
        clear_screen
        run_script "${SCRIPT_NAMES[0]}"
        wait_return
        ;;
      2)
        clear_screen
        run_script "${SCRIPT_NAMES[1]}"
        wait_return
        ;;
      3)
        clear_screen
        run_script "${SCRIPT_NAMES[0]}"
        run_script "${SCRIPT_NAMES[1]}"
        wait_return
        ;;
      0 | q | Q | exit)
        clear_screen
        exit 0
        ;;
      "")
        ;;
      *)
        echo -e "${RED}  Неверный выбор: ${choice}${NC}"
        ;;
    esac
  done
}

main "$@"
