#!/bin/bash

# СЮДА ВСТАВЬ СВОЙ РЕАЛЬНЫЙ ПУБЛИЧНЫЙ КЛЮЧ
PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILxRh4olNu6cTCz7KfIoUVu1O7g5yCN/You2Fp8QkWvY"

echo "=== 1. Обновление и очистка сервера ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y && apt-get autoremove -y

echo "=== 2. Настройка каталога SSH и добавление ключа ==="
mkdir -p ~/.ssh
chmod 700 ~/.ssh

if ! grep -qF "$PUBLIC_KEY" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
    echo "Ключ успешно прописан."
fi
chmod 600 ~/.ssh/authorized_keys

echo "=== 3. Настройка sshd_config ==="
SSHD_CONFIG="/etc/ssh/sshd_config"

# Бэкап конфига
cp $SSHD_CONFIG "${SSHD_CONFIG}.bak"

set_ssh_param() {
    local param=$1
    local value=$2
    if grep -q "^#\?$param" $SSHD_CONFIG; then
        sed -i "s/^#\?$param.*/$param $value/" $SSHD_CONFIG
    else
        echo "$param $value" >> $SSHD_CONFIG
    fi
}

set_ssh_param "PasswordAuthentication" "no"
set_ssh_param "PermitRootLogin" "prohibit-password"
set_ssh_param "PubkeyAuthentication" "yes"
set_ssh_param "AuthorizedKeysFile" ".ssh/authorized_keys"

echo "=== 4. Перезапуск службы SSH ==="
systemctl restart ssh

echo "=== ВСЁ ГОТОВО! ==="
echo "Жень, проверяй вход по ключу в новом окне терминала."
