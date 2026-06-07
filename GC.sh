#!/bin/bash
set -e # Жёстко останавливаем скрипт при любой ошибке!

# 1. Загружаем кириллический шрифт для текущей консоли (Live CD)
setfont cyr-sun16 2>/dev/null || setfont ter-v16n 2>/dev/null || true

echo "============================================="
echo "   Добро пожаловать в UEFI-установщик Mirage OS   "
echo "============================================="

echo "Доступные РЕАЛЬНЫЕ жесткие диски в системе:"
lsblk -d -o NAME,SIZE,TYPE,MODEL | grep "disk" | grep -v "loop" || true
echo "---------------------------------------------"
echo -n "Введите имя диска для установки (например, sda или vda): "
read TARGET_DISK

DISK_PATH="/dev/${TARGET_DISK}"

# ЗАЩИТА: Проверяем диск на Read-Only
if [ -f "/sys/block/${TARGET_DISK}/ro" ]; then
    if [ "$(cat /sys/block/${TARGET_DISK}/ro)" -eq "1" ]; then
        echo "❌ КРИТИЧЕСКАЯ ОШИБКА: Диск $DISK_PATH защищен от записи!"
        exit 1
    fi
fi

echo "ВНИМАНИЕ! Разметка диска $DISK_PATH под UEFI (GPT)..."
# Создаём таблицу GPT и два раздела: EFI (512MB) и ROOT (всё оставшееся место)
parted -s "$DISK_PATH" mklabel gpt
parted -s "$DISK_PATH" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK_PATH" set 1 esp on
parted -s "$DISK_PATH" mkpart primary ext4 513MiB 100%

# Учитываем разный нейминг для дисков (nvme0n1p1 vs sda1)
if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"loop"* ]]; then
    TARGET_EFI="${DISK_PATH}p1"
    TARGET_ROOT="${DISK_PATH}p2"
else
    TARGET_EFI="${DISK_PATH}1"
    TARGET_ROOT="${DISK_PATH}2"
fi

echo "Форматирование разделов..."
mkfs.vfat -F 32 "$TARGET_EFI"  # EFI раздел ОБЯЗАН быть в fat32
mkfs.ext4 -F "$TARGET_ROOT"

echo "Подготовка и монтирование корневого раздела..."
mkdir -p /mnt/target
mount "$TARGET_ROOT" /mnt/target

echo "Распаковка системы Mirage OS (офлайн-режим)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tar -xpvf "$SCRIPT_DIR/mcl_rootfs.tar.xz" -C /mnt/target/ --numeric-owner --xattrs --acls

# Теперь монтируем EFI раздел внутрь скопированной системы
mkdir -p /mnt/target/boot/efi
mount "$TARGET_EFI" /mnt/target/boot/efi

echo "---------------------------------------------"
echo "Монтирование системных интерфейсов (Критично для locale-gen!)..."
mount --types proc /proc /mnt/target/proc
mount --rbind /sys /mnt/target/sys
mount --make-rslave /mnt/target/sys
mount --rbind /dev /mnt/target/dev
mount --make-rslave /mnt/target/dev
mount --bind /run /mnt/target/run
mount --make-slave /mnt/target/run

echo "---------------------------------------------"
echo "Генерация /etc/fstab..."
UUID_ROOT=$(blkid -s UUID -o value $TARGET_ROOT)
UUID_EFI=$(blkid -s UUID -o value $TARGET_EFI)

cat << EOF > /mnt/target/etc/fstab
# <file system> <mount point>   <type>  <options>               <dump>  <pass>
UUID=$UUID_ROOT   /               ext4    defaults,noatime        0       1
UUID=$UUID_EFI    /boot/efi       vfat    defaults                0       2
proc              /proc           proc    defaults                0       0
shm               /dev/shm        tmpfs   nodev,nosuid,noexec     0       0
EOF
echo "/etc/fstab успешно сгенерирован! ✅"

echo "---------------------------------------------"
echo "Настройка даты и времени"
echo -n "Введите регион (например, Europe): "
read REGION
echo -n "Введите город (например, Moscow): "
read CITY

echo "${REGION}/${CITY}" > /mnt/target/etc/timezone
rm -f /mnt/target/etc/localtime
ln -sf /usr/share/zoneinfo/${REGION}/${CITY} /mnt/target/etc/localtime

echo "---------------------------------------------"
echo "Настройка русской локализации (теперь не упадёт!)..."
echo "en_US.UTF-8 UTF-8" > /mnt/target/etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /mnt/target/etc/locale.gen
chroot /mnt/target locale-gen
echo 'LANG="ru_RU.UTF-8"' > /mnt/target/etc/env.d/02locale
chroot /mnt/target env-update

echo "---------------------------------------------"
echo "Выбор графического окружения:"
echo "1) Hyprland 🥞"
echo "2) Только чистая консоль"
read -p "Твой выбор: " DE_CHOICE

if [ "$DE_CHOICE" == "1" ]; then
    cat << 'EOF' > /mnt/target/etc/local.d/mirage-setup.start
#!/bin/bash
mirage install gui-wm/hyprland gui-term/kitty
rm -- "$0"
EOF
    chmod +x /mnt/target/etc/local.d/mirage-setup.start
fi

echo "---------------------------------------------"
echo "Установка загрузчика GRUB в режиме UEFI..."
# Добавляем установку EFI-маркера, чтобы GRUB понял UEFI-окружение хоста
mkdir -p /mnt/target/sys/firmware/efi/efivars 2>/dev/null || true
chroot /mnt/target grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MirageOS --recheck
chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg

echo "---------------------------------------------"
echo "Установка паролей..."
chroot /mnt/target passwd
chroot /mnt/target useradd -m -G wheel,audio,video,usb -s /bin/bash mirage || true
chroot /mnt/target passwd mirage

echo "---------------------------------------------"
echo "Безопасное размонтирование..."
umount -l /mnt/target/dev
umount -l /mnt/target/sys
umount -l /mnt/target/proc
umount -l /mnt/target/run
umount -R /mnt/target

echo "============================================="
echo "   Установка Mirage OS под UEFI успешно завершена! ✅   "
echo "============================================="
