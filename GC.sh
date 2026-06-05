#!/bin/bash
set -e # Жёстко останавливаем скрипт при любой ошибке!

echo "============================================="
echo "   Добро пожаловать в установщик Mirage OS   "
echo "============================================="

echo "Доступные диски в системе:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
echo "---------------------------------------------"
echo -n "Введите имя диска для установки (например, sda или vda): "
read TARGET_DISK

DISK_PATH="/dev/${TARGET_DISK}"

echo "ВНИМАНИЕ! Разметка диска $DISK_PATH..."
# Создаём таблицу MBR и два раздела: 512 МБ под загрузчик и всё остальное под систему
parted -s "$DISK_PATH" mklabel msdos
parted -s "$DISK_PATH" mkpart primary ext4 1MiB 513MiB
parted -s "$DISK_PATH" mkpart primary ext4 513MiB 100%
parted -s "$DISK_PATH" set 1 boot on

# Учитываем разный нейминг для дисков (nvme0n1p1 vs sda1)
if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"loop"* ]]; then
    TARGET_BOOT="${DISK_PATH}p1"
    TARGET_ROOT="${DISK_PATH}p2"
else
    TARGET_BOOT="${DISK_PATH}1"
    TARGET_ROOT="${DISK_PATH}2"
fi

echo "Форматирование разделов в ext4..."
mkfs.ext4 -F "$TARGET_BOOT"
mkfs.ext4 -F "$TARGET_ROOT"

echo "Подготовка и монтирование разделов..."
mkdir -p /mnt/target
mount "$TARGET_ROOT" /mnt/target
mkdir -p /mnt/target/boot
mount "$TARGET_BOOT" /mnt/target/boot

echo "Распаковка системы Mirage OS (офлайн-режим)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tar -xpvf "$SCRIPT_DIR/mcl_rootfs.tar.xz" -C /mnt/target/

echo "---------------------------------------------"
echo "Настройка даты и времени"
echo -n "Введите регион (например, Europe): "
read REGION
echo -n "Введите город (например, Rome): "
read CITY

echo "${REGION}/${CITY}" > /mnt/target/etc/timezone
# Обязательно удаляем старый файл перед созданием симлинка
rm -f /mnt/target/etc/localtime
ln -sf /usr/share/zoneinfo/${REGION}/${CITY} /mnt/target/etc/localtime
echo "Часовой пояс успешно установлен на ${REGION}/${CITY}! ✅"

echo "---------------------------------------------"
echo "Выбор графического окружения:"
echo "1) Hyprland (KISS, Wayland, Плавный фреймрейт) 🥞"
echo "2) Только чистая консоль (Minimal)"
echo -n "Твой выбор: "
read DE_CHOICE

if [ "$DE_CHOICE" == "1" ]; then
    echo "Пользователь выбрал Hyprland."
    cat << 'EOF' > /mnt/target/etc/local.d/mirage-setup.start
#!/bin/bash
echo "Установка графического окружения Hyprland..."
mirage install gui-wm/hyprland gui-term/kitty
rm -- "$0"
EOF
    chmod +x /mnt/target/etc/local.d/mirage-setup.start
fi

echo "Подготовка системного окружения и установка загрузчика GRUB..."
# Правильные бинды для chroot (жизненно важно для установки загрузчика)
mount --types proc /proc /mnt/target/proc
mount --rbind /sys /mnt/target/sys
mount --make-rslave /mnt/target/sys
mount --rbind /dev /mnt/target/dev
mount --make-rslave /mnt/target/dev
mount --bind /run /mnt/target/run
mount --make-slave /mnt/target/run

chroot /mnt/target grub-install "$DISK_PATH"
chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg

echo "============================================="
echo "   Установка Mirage OS успешно завершена! ✅   "
echo "============================================="