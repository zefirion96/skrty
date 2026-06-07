#!/bin/bash
set -e 

echo "=========================================================="
echo "   Установщик MaineCoon Linux (UEFI-режим / Gentoo-base)  "
echo "=========================================================="

lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
echo -n "Введите имя диска (sda/vda): "
read TARGET_DISK
DISK_PATH="/dev/${TARGET_DISK}"

echo "Создание GPT-разметки и разделов..."
parted -s "$DISK_PATH" mklabel gpt
parted -s "$DISK_PATH" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK_PATH" set 1 esp on
parted -s "$DISK_PATH" mkpart primary ext4 513MiB 100%

# Определение имен разделов
if [[ "$TARGET_DISK" == *"nvme"* ]]; then
    TARGET_EFI="${DISK_PATH}p1"
    TARGET_ROOT="${DISK_PATH}p2"
else
    TARGET_EFI="${DISK_PATH}1"
    TARGET_ROOT="${DISK_PATH}2"
fi

echo "Форматирование..."
mkfs.vfat -F 32 "$TARGET_EFI"
mkfs.ext4 -F "$TARGET_ROOT"

echo "Монтирование..."
mkdir -p /mnt/target
mount "$TARGET_ROOT" /mnt/target
mkdir -p /mnt/target/boot/efi
mount "$TARGET_EFI" /mnt/target/boot/efi

echo "Распаковка системы..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tar -xpvf "$SCRIPT_DIR/mcl_rootfs.tar.xz" -C /mnt/target/

echo "Настройка времени..."
echo -n "Введите регион/город (например, Europe/Moscow): "
read ZONE
mkdir -p /mnt/target/etc
ln -sf /usr/share/zoneinfo/$ZONE /mnt/target/etc/localtime

echo "Монтирование системных интерфейсов..."
mount --types proc /proc /mnt/target/proc
mount --rbind /sys /mnt/target/sys
mount --make-rslave /mnt/target/sys
mount --rbind /dev /mnt/target/dev
mount --make-rslave /mnt/target/dev
mount --bind /run /mnt/target/run
mount --make-slave /mnt/target/run
# Критично для записи в NVRAM BIOS из чрута
mount -t efivarfs efivarfs /mnt/target/sys/firmware/efi/efivars/ || true

echo "Установка GRUB (UEFI)..."
# Устанавливаем с именем MaineCoon Linux
chroot /mnt/target grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="MaineCoon Linux" --recheck

# Создаем fallback (на случай сброса BIOS)
mkdir -p /mnt/target/boot/efi/EFI/BOOT
cp /mnt/target/boot/efi/EFI/"MaineCoon Linux"/grubx64.efi /mnt/target/boot/efi/EFI/BOOT/BOOTX64.EFI || true

chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg

echo "=========================================================="
echo "   Установка завершена! Перезагрузитесь. ✅              "
echo "=========================================================="
