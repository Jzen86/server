#!/bin/bash

# СЮДА ВСТАВЬ СВОЙ РЕАЛЬНЫЙ ПУБЛИЧНЫЙ КЛЮЧ
PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILxRh4olNu6cTCz7KfIoUVu1O7g5yCN/You2Fp8QkWvY"

echo "=== 1. Обновление и очистка сервера ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y && apt-get autoremove -y

echo "=== 2. Настройка каталога SSH и добавление ключа ==="
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys

if ! grep -qF "$PUBLIC_KEY" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
    echo "Ключ успешно прописан."
fi
chmod 600 ~/.ssh/authorized_keys

echo "=== 3. Настройка sshd_config (добавление в начало) ==="
SSHD_CONFIG="/etc/ssh/sshd_config"

# Делаем бэкап оригинала
cp $SSHD_CONFIG "${SSHD_CONFIG}.bak"

# Создаем временный файл с твоими кастомными настройками
cat << EOF > /tmp/sshd_custom
PasswordAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
ClientAliveInterval 10
ClientAliveCountMax 60
EOF

# Склеиваем: новые настройки сверху + старый конфиг снизу
cat /tmp/sshd_custom $SSHD_CONFIG > /tmp/sshd_combined && mv /tmp/sshd_combined $SSHD_CONFIG

# Подчищаем временный мусор
rm /tmp/sshd_custom

echo "=== 4. Перезапуск службы SSH ==="
systemctl restart ssh

echo "=== ВСЁ ГОТОВО! ==="
echo "Жень, проверяй вход по ключу в новом окне терминала (старое не закрывай!)."
