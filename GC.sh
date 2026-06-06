#!/bin/bash
set -e # Жёстко останавливаем скрипт при любой ошибке!

# 1. Загружаем кириллический шрифт для текущей консоли (Live CD), чтобы русский текст отображался корректно
setfont cyr-sun16 2>/dev/null || setfont ter-v16n 2>/dev/null || true

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
echo "Генерация /etc/fstab (Паспорт дисков)..."
cat << EOF > /mnt/target/etc/fstab
# <file system> <mount point>   <type>  <options>               <dump>  <pass>
$TARGET_ROOT   /               ext4    defaults,noatime        0       1
$TARGET_BOOT   /boot           ext4    defaults,noatime        0       2
proc           /proc           proc    defaults                0       0
shm            /dev/shm        tmpfs   nodev,nosuid,noexec     0       0
EOF
echo "/etc/fstab успешно сгенерирован! ✅"

echo "---------------------------------------------"
echo "Настройка даты и времени"
echo -n "Введите регион (например, Europe): "
read REGION
echo -n "Введите город (например, Moscow): "
read CITY

echo "${REGION}/${CITY}" > /mnt/target/etc/timezone
# Обязательно удаляем старый файл перед созданием симлинка
rm -f /mnt/target/etc/localtime
ln -sf /usr/share/zoneinfo/${REGION}/${CITY} /mnt/target/etc/localtime
echo "Часовой пояс успешно установлен на ${REGION}/${CITY}! ✅"

echo "---------------------------------------------"
echo "Настройка русской локализации в системе..."
# Прописываем локали для генерации
echo "en_US.UTF-8 UTF-8" > /mnt/target/etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /mnt/target/etc/locale.gen
# Генерируем локали внутри чрута
chroot /mnt/target locale-gen
# Устанавливаем русский язык по умолчанию для всей системы
echo 'LANG="ru_RU.UTF-8"' > /mnt/target/etc/env.d/02locale
chroot /mnt/target env-update
echo "Локализация настроена! ✅"

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

echo "---------------------------------------------"
echo "Подготовка системного окружения..."
# Правильные бинды для chroot (жизненно важно для установки загрузчика)
mount --types proc /proc /mnt/target/proc
mount --rbind /sys /mnt/target/sys
mount --make-rslave /mnt/target/sys
mount --rbind /dev /mnt/target/dev
mount --make-rslave /mnt/target/dev
mount --bind /run /mnt/target/run
mount --make-slave /mnt/target/run

echo "Установка загрузчика GRUB..."
chroot /mnt/target grub-install "$DISK_PATH"
chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg

echo "---------------------------------------------"
echo "Установка пароля для суперпользователя (root):"
chroot /mnt/target passwd

echo "---------------------------------------------"
echo "Создание обычного пользователя 'mirage':"
chroot /mnt/target useradd -m -G wheel,audio,video,usb -s /bin/bash mirage || true
chroot /mnt/target passwd mirage

echo "============================================="
echo "   Установка Mirage OS успешно завершена! ✅   "
echo "   Теперь можно ввести 'reboot' для запуска! "
echo "============================================="
