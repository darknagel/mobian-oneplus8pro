#!/bin/bash
# Build oneplus-instantnoodlep-support_*.deb for Mobian from the v2026.11.22 release rootfs
# (mounted read-only by mount-release.sh). Local package, not for publishing:
# it carries the same firmware blobs the pmOS image ships.
#   RELEASE_DIR=/path/to/release-2026-11-22 build-support-deb.sh
set -euo pipefail
WORK=${WORK:-$HOME/mobian}
HERE=$(cd "$(dirname "$0")/.." && pwd)
RELEASE_DIR=${RELEASE_DIR:?set RELEASE_DIR to the unpacked release (for dtbo.img)}
R=$WORK/relmnt
OUT=$WORK/debs
VER=2026.11.22-7
P=$WORK/support-pkg
rm -rf "$P"; mkdir -p "$P/DEBIAN" "$OUT"

# copy keeping relative path
cpr() { for f in "$@"; do mkdir -p "$P/$(dirname "$f")"; sudo cp -a "$R/$f" "$P/$f"; done; }

cd "$R"
# device package (pmOS device-oneplus-instantnoodlep), minus pmOS-only bits
cpr usr/lib/systemd/system/hexagonrpcd-sdsp.service.d/writable-registry.conf \
    usr/lib/systemd/system/iio-sensor-proxy.service.d/restart.conf \
    usr/lib/tmpfiles.d/hexagonrpcd-oneplus-instantnoodlep.conf \
    usr/lib/udev/rules.d/81-libssc-oneplus-instantnoodlep.rules
mkdir -p "$P/usr/share/oneplus-instantnoodlep"
sudo cp "$RELEASE_DIR/dtbo.img" "$P/usr/share/oneplus-instantnoodlep/dtbo.img"

# firmware packages
cpr usr/lib/firmware/postmarketos/adsp.mbn usr/lib/firmware/postmarketos/slpi.mbn \
    usr/lib/firmware/qcom/sm8250/OnePlus/instantnoodlep/a650_zap.mbn
# Bluetooth: Debian's firmware-atheros owns /usr/lib/firmware/qca; the kernel
# looks in updates/ first, so the OnePlus files win without a file conflict
mkdir -p "$P/usr/lib/firmware/updates/qca"
sudo cp -a usr/lib/firmware/qca/. "$P/usr/lib/firmware/updates/qca/"

# UCM
mkdir -p "$P/usr/share/alsa/ucm2/conf.d/sm8250"
sudo cp -a usr/share/alsa/ucm2/OnePlus8Pro "$P/usr/share/alsa/ucm2/"
sudo cp -a "usr/share/alsa/ucm2/conf.d/sm8250/OnePlus 8 Pro.conf" "$P/usr/share/alsa/ucm2/conf.d/sm8250/"

# release postprocess files
for f in $(find usr/local etc/modprobe.d etc/udev/rules.d etc/wireplumber etc/systemd/resolved.conf.d etc/systemd/system \
           -maxdepth 3 -type f | grep -v -E '^etc/modprobe.d/(aliases|blacklist|i386)\.conf|^etc/systemd/system/(autovt@|ctrl-alt-del|dbus)'); do
  cpr "$f"
done
mkdir -p "$P/var/lib/sdx55-rfs/efs"; chmod 700 "$P/var/lib/sdx55-rfs/efs"

# Firmware scripts from the repo: they also find the slot with qbootctl, the
# bootloader passes no androidboot.slot_suffix to Mobian's boot image
inst() { sudo mkdir -p "$P/$(dirname "$2")"; sed 's/\r$//' "$1" | sudo tee "$P/$2" >/dev/null; sudo chmod "$3" "$P/$2"; }
inst $HERE/shared/dsp-firmware.sh usr/local/bin/dsp-firmware 755
inst $HERE/shared/sdx55-firmware.sh usr/local/bin/sdx55-firmware 755
inst $HERE/shared/rfsd.py usr/local/bin/sdx55-rfsd 755
# pil-squasher is not packaged in Debian (built from github.com/linux-msm/pil-squasher)
sudo install -Dm755 "${PIL_SQUASHER:-$WORK/pil-squasher}" "$P/usr/local/bin/pil-squasher"
# droid-juicer: protection domain maps from the modem partition for pd-mapper
inst "$HERE/device/droid-juicer/oneplus,instantnoodlep.toml" "usr/share/droid-juicer/configs/oneplus,instantnoodlep.toml" 644

# initramfs: charger ADC early (pmOS modules-initfs); remoteproc/MHI only from the root fs
mkdir -p "$P/usr/share/initramfs-tools/modules.d"
echo qcom-spmi-adc5 > "$P/usr/share/initramfs-tools/modules.d/oneplus-instantnoodlep.conf"
inst $HERE/device/initramfs/initramfs-hook-oneplus-instantnoodlep usr/share/initramfs-tools/hooks/oneplus-instantnoodlep 755

# QCA6390 has no MAC address from the bootloader and gets a new one each boot
sudo mkdir -p "$P/usr/lib/NetworkManager/conf.d"
printf '[connection-wifi-stable-mac]\nmatch-device=interface-name:wlp1s0\nwifi.cloned-mac-address=stable\n' | \
  sudo tee "$P/usr/lib/NetworkManager/conf.d/90-oneplus-instantnoodlep-wifi-mac.conf" >/dev/null

# Sensor DSP: hexagonrpcd-sdsp.service as on pmOS (Debian's hexagonrpcd.service
# picks the ADSP on SM8250); the writable-registry drop-in above applies to it
inst $HERE/device/systemd/hexagonrpcd-sdsp.service usr/lib/systemd/system/hexagonrpcd-sdsp.service 644
inst $HERE/device/systemd/hexagonrpcd-sdsp-writable-registry.conf usr/lib/systemd/system/hexagonrpcd-sdsp.service.d/writable-registry.conf 644
# accelerometer and proximity over libssc (pmOS ships this with iio-sensor-proxy;
# upstream turned proximity off)
inst $HERE/device/udev/90-iio-sensor-proxy-proximity-sensor-enable.rules usr/lib/udev/rules.d/90-iio-sensor-proxy-proximity-sensor-enable.rules 644

cat > "$P/DEBIAN/control" <<EOF
Package: oneplus-instantnoodlep-support
Version: $VER
Architecture: arm64
Maintainer: local build <noreply@localhost>
Depends: python3, python3-gi, erofs-utils, systemd, qbootctl, hexagonrpcd (>= 0.5.0)
Recommends: iio-sensor-proxy, modemmanager, bluez, alsa-ucm-conf, fprintd
Description: OnePlus 8 Pro (instantnoodlep) device support for Mobian
 Firmware, DSP/modem/GNSS helper services, ALSA UCM, udev and modprobe
 configuration taken from the unofficial mainline port (release v2026.11.22).
EOF

UNITS="hexagonrpcd-sdsp.service dsp-firmware.service sdx55-firmware.service sdx55-rfsd.service sdx55-gnss.service sdx55-sim.service sdx55-callaudio.service ois-gyro.service oneplus-ota-fetch.service slpi-guard.service grow-rootfs.service"
cat > "$P/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
if [ "\$1" = configure ]; then
  systemctl enable $UNITS >/dev/null 2>&1 || true
  mkdir -p /etc/systemd/system/sleep.target.wants
  ln -sf /etc/systemd/system/sdx55-gnss-sleep.service /etc/systemd/system/sleep.target.wants/sdx55-gnss-sleep.service
  systemctl disable tqftpserv.service >/dev/null 2>&1 || true
  # Mobian's QMI setup talks to the modem while the sdx55-* services bring it up
  systemctl disable qcom-modem-setup.service >/dev/null 2>&1 || true
  # Debian's generic sensor daemon unit would grab the ADSP; ours serves the SDSP
  systemctl disable hexagonrpcd.service >/dev/null 2>&1 || true
  command -v update-initramfs >/dev/null && update-initramfs -u || true
fi
EOF
cat > "$P/DEBIAN/prerm" <<EOF
#!/bin/sh
set -e
[ "\$1" = remove ] && systemctl disable $UNITS >/dev/null 2>&1 || true
rm -f /etc/systemd/system/sleep.target.wants/sdx55-gnss-sleep.service
EOF
chmod 755 "$P/DEBIAN/postinst" "$P/DEBIAN/prerm"
# conffiles: everything under /etc
( cd "$P" && find etc -type f | sed 's|^|/|' ) > "$P/DEBIAN/conffiles"

sudo chown -R root:root "$P"
sudo dpkg-deb --build --root-owner-group "$P" "$OUT/oneplus-instantnoodlep-support_${VER}_arm64.deb"
dpkg-deb -c "$OUT/oneplus-instantnoodlep-support_${VER}_arm64.deb" | wc -l
ls -l "$OUT"
