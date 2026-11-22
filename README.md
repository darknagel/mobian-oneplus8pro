# Mobian on the OnePlus 8 Pro (instantnoodlep)

Work in progress: [Mobian](https://mobian.org) (Debian forky + Phosh) on the OnePlus 8 Pro
(IN2023, Snapdragon 865), on the same mainline kernel and device work as the
[unofficial Nura/postmarketOS port](https://github.com/darknagel/oneplus-instantnoodlep-nura-unofficial).
Unofficial and independent: not affiliated with or supported by the Mobian project.

There is no image to download yet. This repository holds what turns Mobian's build
([mobian-recipes](https://salsa.debian.org/Mobian-team/mobian-recipes), `qcom-wip` device)
into a working image for this phone: the device configuration, the packaging scripts and the
patches for the Debian packages that need them.

## Status

| Area | State |
|---|---|
| Display, touch, GPU, Phosh | works |
| Wi-Fi, Bluetooth | works |
| Audio | sound card and UCM load; playback not tested yet |
| ADSP, CDSP, SLPI, video firmware | works |
| Modem (SDX55) | detected by ModemManager over QRTR, IMEI read; calls, SMS and data not tested with a SIM yet |
| GPS | NMEA on `/dev/gnss-sdx55` |
| Rotation, light sensor, compass | works |
| Proximity sensor | detected; reacting to "near" not confirmed yet |
| Cameras, fingerprint reader, USB-C role switching | not ported yet (libcamera, libfprint, qsee-supplicant, usb-signaller) |

## How it fits together

- **Kernel**: the port's kernel (pmOS tag `sm8250-7.2.0_git20261010` plus all of the port's
  kernel patches, built from the same config) packaged with `make bindeb-pkg`
  ([scripts/build-kernel-deb.sh](scripts/build-kernel-deb.sh)). `EFI_ZBOOT` is turned off:
  the Android bootloader cannot start an EFI zboot image.
- **Device configuration** for mobian-recipes: [device/wip.toml](device/wip.toml) (boot image
  header v2, dtb offset and kernel command line from the pmOS deviceinfo, plus
  `firmware_class.path=/lib/firmware/postmarketos`, which the pmOS initramfs sets).
- **`oneplus-instantnoodlep-support`** ([scripts/build-support-deb.sh](scripts/build-support-deb.sh)):
  the device files of the port's release image (firmware, ALSA UCM, the services that copy the
  DSP and modem firmware from the phone's own partitions, modem/GNSS/call audio helpers,
  OnePlus OTA fetcher for the sensor configuration and fingerprint TA, udev and modprobe
  configuration), plus what Mobian needs on top:
  - an initramfs hook that leaves the remoteproc and MHI drivers out of the initramfs
    (Mobian's `MODULES=most` loaded them before the firmware is in place),
  - `hexagonrpcd-sdsp.service` for the sensor DSP (Debian's `hexagonrpcd.service` picks the
    ADSP on SM8250) and the udev rule that enables the accelerometer and proximity sensor over
    libssc,
  - a droid-juicer configuration that takes the protection domain maps for pd-mapper from the
    modem partition,
  - `pil-squasher` (not packaged in Debian),
  - a stable Wi-Fi MAC address, and Mobian's `qcom-modem-setup` turned off.
- **Patched Debian packages** ([debpatches/](debpatches), built on the phone with
  [scripts/build-patched-deb.sh](scripts/build-patched-deb.sh) and
  [scripts/build-modem-debs.sh](scripts/build-modem-debs.sh)):
  - ModemManager at the upstream commit the port uses (`7f0bf17`, 1.25.95) with the SDX55
    patches; [0007](debpatches/modemmanager/0007-build-with-libqmi-1.38.patch) builds it with
    Debian's libqmi 1.38,
  - 81voltd 1.2.0 (VoLTE) with the port's three patches,
  - hexagonrpcd 0.5.0 with the port's patches (writable sensor registry), packaged on Debian's
    0.4 packaging,
  - iio-sensor-proxy 3.9 with the port's patch.
- [shared/](shared): the port's firmware scripts with a fallback that finds the active slot
  with `qbootctl`, because the bootloader passes no `androidboot.slot_suffix` to Mobian's boot
  image. These changes belong in the port repository as well.

The support package contains firmware files from the port's release image, so built packages
and images are not published here.

## Build

Everything was built from WSL2 (Ubuntu 24.04) and on the phone itself.

1. Kernel: a pmaports checkout with the port's patch series applied (see the port's README,
   "Build it yourself"), then `scripts/build-kernel-deb.sh` (`PMAPORTS`, `KERNEL_TARBALL`,
   `WORK` can be set).
2. Support package: unpack the port's release v2026.11.22 rootfs
   (`simg2img oneplus-instantnoodlep-rootfs.img rootfs.raw`), `scripts/mount-release.sh rootfs.raw`,
   build [pil-squasher](https://github.com/linux-msm/pil-squasher) for arm64, then
   `RELEASE_DIR=... scripts/build-support-deb.sh`.
3. Patched packages, on a phone running Mobian: copy `debpatches/` to `~/build/patches/`,
   install the build dependencies as root (`scripts/build-modem-deps.sh`,
   `apt-get build-dep hexagonrpcd iio-sensor-proxy`, `libjson-c-dev`), then
   `scripts/build-modem-debs.sh` and
   `scripts/build-patched-deb.sh hexagonrpcd np1 https://github.com/linux-msm/hexagonrpc/archive/refs/tags/v0.5.0.tar.gz 0.5.0`,
   `scripts/build-patched-deb.sh iio-sensor-proxy np1`.
4. Image: copy `device/wip.toml` to `devices/qcom/configs/wip.toml` in mobian-recipes, put the
   kernel, support and patched `.deb`s into `devices/qcom/packages/`, change the
   "Install additional packages" step in `devices/qcom/packages-base.yaml` from `dpkg -i` to
   `apt-get install -y /srv/*.deb` (the packages have dependencies), then
   `./build.sh -t qcom-wip -e phosh -s`. In WSL without KVM: `ARGS=--disable-fakemachine`, and
   run `scripts/wsl-prep.sh` as root first (qemu binfmt, udevd, `/dev/disk`).
5. Flash in fastboot: `boot_a` (or `_b`) with the boot image, `dtbo` with the port's
   `dtbo.img`, `super` with the rootfs image. This wipes the phone.

After changing the initramfs on the phone, write the boot image again with
`/etc/kernel/postinst.d/zz-qcom-bootimg $(uname -r)`; Mobian does this only on kernel updates.
[scripts/bootimg-append-cmdline.sh](scripts/bootimg-append-cmdline.sh) changes the kernel
command line of the flashed boot image.

## Known issues

- One `systemctl reboot` hung on the Mobian splash screen. Since the splash is off
  (`plymouth.enable=0`) and `DefaultTimeoutStopSec=20s`, reboots have worked; the cause is not
  known.
- Mobian's USB networking (CDC ECM) has no driver on Windows; use Wi-Fi for SSH.
- ModemManager's MediaTek and Rolling plugins fail to load (warnings only); the port builds
  without them.

## License

Each patch keeps the license of the project it applies to. Scripts and configuration files are
under the same terms as the [port repository](https://github.com/darknagel/oneplus-instantnoodlep-nura-unofficial).
