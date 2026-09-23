#!/bin/bash
# build.sh - воспроизводимая сборка драйверов RT3070 (rt2800usb) и mac80211
# под ядро ImmortalWrt 6.12.85 (target sunxi/cortexa53).
#
# Собирает модули из исходников ImmortalWrt на ТОМ ЖЕ коммите, из которого
# собрана прошивка приставки, поэтому итоговый vermagic совпадает:
#   "6.12.85 SMP mod_unload aarch64"
#
# Запускать на x86_64 Linux (проверено на Debian/Kali). Нужен интернет.
# Результат складывается в ./artifacts (modules/*.ko и packages/*.apk).
set -eux
export LC_ALL=C
export FORCE_UNSAFE_CONFIGURE=1

# Полный SHA коммита прошивки: ImmortalWrt 25.12-SNAPSHOT r0+37823-bce0a385ed
COMMIT="${COMMIT:-bce0a385ed95e93bc86bd6ff3e5ec5fb25293454}"
WORK="${WORK:-$HOME/immortalwrt}"
OUT="${OUT:-$(pwd)/artifacts}"

# --- 1. Хостовые зависимости (Debian/Ubuntu/Kali) --------------------------
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential clang flex bison g++ gawk gettext git \
    libncurses-dev libssl-dev python3 python3-setuptools \
    rsync swig unzip zlib1g-dev file wget zstd
fi

# --- 2. Исходники строго на коммите прошивки (shallow) ---------------------
if [ ! -d "$WORK/.git" ]; then
  git init "$WORK"
  cd "$WORK"
  git remote add origin https://github.com/immortalwrt/immortalwrt.git
  git fetch --depth 1 origin "$COMMIT"
  git checkout -f FETCH_HEAD
fi
cd "$WORK"
git log -1 --oneline

# Проверяем, что это действительно ядро 6.12.85
grep -q 'LINUX_VERSION-6.12 = .85' target/linux/generic/kernel-6.12 \
  || { echo "Это не ядро 6.12.85 — коммит неверный"; exit 1; }

# --- 3. Конфигурация: target sunxi/cortexa53 + нужные модули ---------------
# Feeds не нужны: cfg80211/mac80211/rt2x00/rt2800 лежат в core-дереве.
: > .config
cat >> .config <<'EOF'
CONFIG_TARGET_sunxi=y
CONFIG_TARGET_sunxi_cortexa53=y
CONFIG_PACKAGE_kmod-rt2800-usb=m
CONFIG_PACKAGE_kmod-rt2800-lib=m
CONFIG_PACKAGE_kmod-rt2x00-usb=m
CONFIG_PACKAGE_kmod-rt2x00-lib=m
CONFIG_PACKAGE_kmod-mac80211=m
CONFIG_PACKAGE_kmod-cfg80211=m
CONFIG_PACKAGE_kmod-eeprom-93cx6=m
CONFIG_PACKAGE_kmod-lib-crc-ccitt=m
CONFIG_PACKAGE_iw=y
CONFIG_PACKAGE_wireless-regdb=y
CONFIG_PACKAGE_rt2800-usb-firmware=y
EOF
make defconfig

# --- 4. Сборка -------------------------------------------------------------
make -j"$(nproc)" tools/install
make -j"$(nproc)" toolchain/install
make -j"$(nproc)" target/linux/compile
make -j"$(nproc)" package/kernel/mac80211/compile
make -j"$(nproc)" package/network/utils/iw/compile package/firmware/wireless-regdb/compile

# --- 5. Сбор артефактов ----------------------------------------------------
rm -rf "$OUT"; mkdir -p "$OUT/modules" "$OUT/packages"
PB="build_dir/target-aarch64_cortex-a53_musl/linux-sunxi_cortexa53/mac80211-regular/backports-6.18.26/.pkgdir"
LX="build_dir/target-aarch64_cortex-a53_musl/linux-sunxi_cortexa53/linux-6.12.85"
for m in compat cfg80211 mac80211 rt2x00lib rt2x00usb rt2800lib rt2800usb eeprom_93cx6; do
  f="$(find "$PB" "$LX" -path '*/6.12.85/*' -name "$m.ko" 2>/dev/null | head -1)"
  cp "$f" "$OUT/modules/"
done
find bin -name 'iw-*.apk'                -exec cp {} "$OUT/packages/" \;
find bin -name 'wireless-regdb-*.apk'    -exec cp {} "$OUT/packages/" \;
find bin -name 'rt2800-usb-firmware-*.apk' -exec cp {} "$OUT/packages/" \;

echo "=== vermagic ==="
strings "$OUT/modules/rt2800usb.ko" | sed -n 's/^vermagic=/vermagic=/p' | head -1
echo "=== артефакты в $OUT ==="
ls -la "$OUT/modules" "$OUT/packages"
