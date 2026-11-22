#!/bin/bash
# Build the OnePlus 8 Pro mainline kernel (pmOS tag + all port patches) as Debian packages.
set -euo pipefail
# pmaports checkout with the port's patch series applied (see README), and the
# kernel tarball pmbootstrap downloaded for it
PMAPORTS=${PMAPORTS:-$HOME/.local/var/pmbootstrap/cache_git/pmaports}
PKG=$PMAPORTS/device/testing/linux-postmarketos-qcom-sm8250
TAR=${KERNEL_TARBALL:-$HOME/.local/var/pmbootstrap/cache_distfiles/linux-postmarketos-qcom-sm8250-sm8250-7.2.0_git20261010.tar.gz}
OUT=${WORK:-$HOME/mobian}/kernel
SRC=$OUT/linux

echo "pmaports: $(git -C $PKG rev-parse --abbrev-ref HEAD) $(git -C $PKG log --oneline -1)"
grep -E '^pkgrel=' $PKG/APKBUILD

rm -rf "$SRC"; mkdir -p "$OUT"
tar -xzf "$TAR" -C "$OUT"
mv "$OUT"/linux-sm8250-7.2.0_git20261010 "$SRC"

# apply patches in APKBUILD order
cd "$SRC"
n=0
for p in $(sed -n '/^source="/,/^"/p' $PKG/APKBUILD | grep -E '\.patch$' | tr -d '\t '); do
  patch -p1 -s -N < "$PKG/$p"; n=$((n+1))
done
echo "applied $n patches"

cp $PKG/config-postmarketos-qcom-sm8250.aarch64 .config
# Debian/Mobian: initramfs-tools initrd, no module signing
./scripts/config -d MODULE_SIG -d SYSTEM_TRUSTED_KEYRING -d EFI_ZBOOT -e BLK_DEV_INITRD
export ARCH=arm64 LLVM=1 KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=mobian
make olddefconfig >/dev/null
time make -j"$(nproc)" LOCALVERSION=-instantnoodlep KDEB_PKGVERSION=7.2.0-1~np1 bindeb-pkg 2>&1 | tail -20
ls -l "$OUT"/*.deb
