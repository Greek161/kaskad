#!/bin/bash

# KASKAD PRO v3.0 RU
# Менеджер проброса портов

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

PORT_DB="/root/kaskad-ports.db"
BACKUP_DIR="/root/kaskad-backups"
EXPORT_DIR="/root/kaskad-exports"

# ============================
# ВАЛИДАЦИЯ
# ============================

validate_ip() {
    local ip=$1
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        for octet in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
            ((octet > 255)) && return 1
        done
        return 0
    fi
    return 1
}

validate_port() {
    local port=$1
    [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}

# ============================
# ПОДГОТОВКА СИСТЕМЫ
# ============================

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}[ОШИБКА] Запустите скрипт от имени root!${NC}"
        exit 1
    fi
}

check_ufw() {
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "${YELLOW}[ВНИМАНИЕ] UFW активен и конфликтует с KASKAD!${NC}"
        read -p "Отключить UFW? [Y/n]: " ans
        [[ "$ans" != "n" && "$ans" != "N" ]] && ufw disable && echo -e "${GREEN}UFW отключён.${NC}"
    fi
}

get_ssh_port() {
    local port
    port=$(grep -oP '^Port\s+\K\d+' /etc/ssh/sshd_config 2>/dev/null)
    [[ -n "$port" ]] && echo "$port" && return
    port=$(ss -tlnp 2>/dev/null | awk '/sshd/ {print $4}' | awk -F: '{print $NF}' | head -n1)
    [[ -n "$port" ]] && echo "$port" || echo 22
}

get_ext_if() {
    local iface
    iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
    [[ -z "$iface" ]] && iface=$(ip route | grep default | awk '{print $5}' | head -n1)
    echo "$iface"
}

prepare_system() {
    SSH_PORT=$(get_ssh_port)
    EXT_IF=$(get_ext_if)

    if [[ -z "$EXT_IF" ]]; then
        echo -e "${RED}[ОШИБКА] Не удалось определить внешний интерфейс!${NC}"
        exit 1
    fi

    echo -e "${CYAN}SSH порт: $SSH_PORT | Внешний интерфейс: $EXT_IF${NC}"

    # Sysctl
    grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1

    # Установка зависимостей
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1
    apt-get install -y iptables-persistent netfilter-persistent curl >/dev/null 2>&1

    # Базовые правила iptables (идемпотентно)
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null && iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -C INPUT -i lo -j ACCEPT 2>/dev/null && iptables -A INPUT -i lo -j ACCEPT
    iptables -C INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT 2>/dev/null && iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null && iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -t nat -C POSTROUTING -o "$EXT_IF" -j MASQUERADE 2>/dev/null && iptables -t nat -A POSTROUTING -o "$EXT_IF" -j MASQUERADE

    # Директории
    mkdir -p "$BACKUP_DIR" "$EXPORT_DIR"
    touch "$PORT_DB"

    save_rules
}

save_rules() {
    netfilter-persistent save >/dev/null 2>&1
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
}

# ============================
# БАЗА ПОРТОВ
# ============================

track_port() {
    echo "$1|$2|$3|$4" >> "$PORT_DB"
}

untrack_port() {
    sed -i "|$1|$2|d" "$PORT_DB"
}

# Добавьте здесь дополнительные функции управления портами по необходимости.

# ============================
# Основная логика
# ============================

main() {
    check_root
    check_ufw
    prepare_system
    echo -e "${GREEN}KASKAD PRO установлен и готов к работе.${NC}"
}

main "$@"
