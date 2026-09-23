#!/bin/sh
# uninstall.sh - удаление драйверов RT3070, установленных install.sh.
set -e
KREL="$(uname -r)"
MODDIR="/lib/modules/$KREL"

echo "[*] Выгружаю модули"
for m in rt2800usb rt2800lib rt2x00usb rt2x00lib eeprom_93cx6 mac80211 cfg80211 compat; do
    rmmod "$m" 2>/dev/null || true
done

echo "[*] Удаляю .ko из $MODDIR"
for m in compat cfg80211 mac80211 eeprom_93cx6 rt2x00lib rt2x00usb rt2800lib rt2800usb; do
    rm -f "$MODDIR/$m.ko"
done

echo "[*] Убираю автозагрузку"
rm -f /etc/modules.d/50-rt2800usb-wifi

echo "[*] Пакеты iw / wireless-regdb / rt2800-usb-firmware оставлены (безвредны)."
echo "    При желании удалите: apk del iw wireless-regdb rt2800-usb-firmware"
echo "[*] Готово."
