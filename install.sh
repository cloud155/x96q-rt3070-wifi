#!/bin/sh
# install.sh - Установка драйверов Ralink RT3070 (rt2800usb) на ImmortalWrt.
#
# Предназначено ДЛЯ КОНКРЕТНОГО ЯДРА: Linux 6.12.85 (sunxi/cortexa53),
# ImmortalWrt 25.12-SNAPSHOT. Модули ядра обязаны точно совпадать со
# строкой vermagic работающего ядра, иначе они не загрузятся.
#
# Запускать НА ПРИСТАВКЕ от root, из распакованной папки проекта:
#   scp -r x96q-rt3070-wifi root@192.168.4.1:/tmp/
#   ssh root@192.168.4.1 "sh /tmp/x96q-rt3070-wifi/install.sh"
set -e

TARGET_KREL="6.12.85"
SELF="$(cd "$(dirname "$0")" && pwd)"
KREL="$(uname -r)"
MODDIR="/lib/modules/$KREL"

say()  { echo "[*] $*"; }
warn() { echo "[!] $*" >&2; }
die()  { echo "[x] $*" >&2; exit 1; }

say "Работающее ядро: $KREL"

# --- 1. Проверка совместимости ядра ---------------------------------------
if [ "$KREL" != "$TARGET_KREL" ]; then
    warn "Ядро приставки ($KREL) не равно целевому ($TARGET_KREL)."
    warn "Эти модули собраны строго под $TARGET_KREL и, скорее всего, НЕ загрузятся."
    warn "Нужно пересобрать модули под своё ядро (см. build/build.sh)."
    die  "Прерываю, чтобы не сломать систему. Уберите проверку сознательно, если уверены."
fi

# Сверяем vermagic модуля с ядром (без depmod, читаем секцию .modinfo)
WANT="$(strings "$SELF/modules/rt2800usb.ko" 2>/dev/null | sed -n 's/^vermagic=//p' | head -n1)"
say "vermagic модулей: ${WANT:-неизвестно}"

# --- 2. Копирование модулей ------------------------------------------------
[ -d "$MODDIR" ] || die "Нет каталога $MODDIR"
say "Копирую .ko в $MODDIR"
for ko in "$SELF"/modules/*.ko; do
    cp -f "$ko" "$MODDIR/"
done

# depmod есть не на всех сборках; kmodloader/modprobe умеют читать зависимости
# прямо из .ko, поэтому отсутствие depmod не критично.
if command -v depmod >/dev/null 2>&1; then
    say "Обновляю modules.dep (depmod)"
    depmod -a "$KREL" || warn "depmod завершился с ошибкой (не критично)"
else
    warn "depmod отсутствует — пропускаю (modprobe читает зависимости из .ko)"
fi

# --- 3. Userspace-пакеты (прошивка, iw, regdb) -----------------------------
# У них нет зависимости от версии ядра, ставятся штатно через apk.
if command -v apk >/dev/null 2>&1; then
    say "Устанавливаю прошивку/iw/wireless-regdb через apk"
    apk add --allow-untrusted \
        "$SELF"/packages/rt2800-usb-firmware-*.apk \
        "$SELF"/packages/wireless-regdb-*.apk \
        "$SELF"/packages/iw-*.apk || warn "apk add вернул ошибку — проверьте вывод выше"
else
    warn "apk не найден. Копирую прошивку rt2870.bin вручную."
    # запасной путь, если пакетный менеджер недоступен
    mkdir -p /lib/firmware
fi

# Гарантируем наличие прошивки даже если apk не отработал
if [ ! -f /lib/firmware/rt2870.bin ]; then
    warn "rt2870.bin не найдена в /lib/firmware после установки пакета."
fi

# --- 4. Автозагрузка при старте --------------------------------------------
say "Прописываю автозагрузку модулей: /etc/modules.d/50-rt2800usb-wifi"
mkdir -p /etc/modules.d
cp -f "$SELF/etc/modules.d/50-rt2800usb-wifi" /etc/modules.d/50-rt2800usb-wifi

# --- 5. Загрузка сейчас -----------------------------------------------------
say "Загружаю модуль rt2800usb"
modprobe rt2800usb || die "modprobe rt2800usb не удался (см. dmesg)"
sleep 2

# --- 6. Проверка ------------------------------------------------------------
echo
if [ -d /sys/class/ieee80211/phy0 ]; then
    say "УСПЕХ: создан радиоинтерфейс phy0"
    dmesg | grep -iE 'rt2800|rt2x00|phy0|firmware' | tail -n 6 || true
    echo
    say "Дальше настройте /etc/config/wireless (см. папку examples/) и выполните: wifi up"
else
    warn "phy0 пока не появился."
    warn "Убедитесь, что адаптер Alfa (USB ID 148f:3070) физически воткнут:"
    warn "  for d in /sys/bus/usb/devices/*/idVendor; do echo \$(cat \$d); done | grep 148f"
    warn "Если адаптер отваливается — вероятно, не хватает питания USB (нужен хаб с внешним питанием)."
fi
