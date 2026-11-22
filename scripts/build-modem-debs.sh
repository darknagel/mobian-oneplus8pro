#!/bin/bash
# Run on the phone (Mobian, arm64) as the mobian user with sudo.
# Builds ModemManager at the pmOS fork's upstream commit + our patches, and
# Debian's 81voltd + our patches, as .deb packages in ~/build/out.
# Patches are expected in ~/build/patches/{modemmanager,81voltd}.
set -euo pipefail
MM_COMMIT=7f0bf17ab518cd78925cf7e53cc0d5c42f88b41a
MM_VER=1.25.95+git20261005
B=$HOME/build
OUT=$B/out
mkdir -p "$OUT"
export DEBEMAIL=noreply@localhost DEBFULLNAME="local build" DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)"

# Build dependencies are installed beforehand as root (see build-modem-deps.sh)

######## ModemManager
cd "$B"; rm -rf mm; mkdir mm; cd mm
apt-get source -qq modemmanager >/dev/null
DEB=$(find . -maxdepth 1 -type d -name 'modemmanager-*' | head -1)
curl -sL -o "modemmanager_${MM_VER}.orig.tar.gz" \
  "https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/archive/${MM_COMMIT}/ModemManager-${MM_COMMIT}.tar.gz"
tar xzf "modemmanager_${MM_VER}.orig.tar.gz"
SRC=ModemManager-${MM_COMMIT}
cp -a "$DEB/debian" "$SRC/"
cd "$SRC"
# Debian's own patches are for 1.24; keep only those that still apply
mkdir -p debian/patches; : > debian/patches/series.new
if [ -f debian/patches/series ]; then
  while read -r p; do
    [ -z "$p" ] && continue
    case "$p" in \#*) continue ;; esac
    if patch -p1 --dry-run -s -f < "debian/patches/$p" >/dev/null 2>&1; then
      patch -p1 -s < "debian/patches/$p"; echo "$p" >> debian/patches/series.new; echo "debian patch ok: $p"
    else
      echo "debian patch dropped: $p"
    fi
  done < debian/patches/series
fi
for p in "$B"/patches/modemmanager/*.patch; do
  cp "$p" debian/patches/
  patch -p1 -s < "$p"; basename "$p" >> debian/patches/series.new
  echo "our patch ok: $(basename "$p")"
done
mv debian/patches/series.new debian/patches/series
# patches are applied in the tree already; format 1.0 keeps dpkg-source from re-applying them
echo "1.0" > debian/source/format
dch -v "${MM_VER}-0np1" -D unstable "OnePlus 8 Pro: pmOS ModemManager fork (upstream ${MM_COMMIT:0:7} + SDX55 patches)"
# the fork adds library symbols; debian/rules pins the strictest symbols check
sed -i 's/^export DPKG_GENSYMBOLS_CHECK_LEVEL=4/export DPKG_GENSYMBOLS_CHECK_LEVEL=0/' debian/rules
# -B: architecture packages only (no gtk-doc, which is broken at this commit)
dpkg-buildpackage -B -uc -us -j"$(nproc)" -d 2>&1 | tail -15
cd ..; cp ./*.deb "$OUT/"

######## 81voltd
cd "$B"; rm -rf voltd; mkdir voltd; cd voltd
apt-get source -qq 81voltd >/dev/null
SRC=$(find . -maxdepth 1 -type d -name '81voltd-*' | head -1)
cd "$SRC"
for p in "$B"/patches/81voltd/*.patch; do
  cp "$p" debian/patches/ 2>/dev/null || { mkdir -p debian/patches; cp "$p" debian/patches/; }
  patch -p1 -s < "$p"; basename "$p" >> debian/patches/series
  echo "our patch ok: $(basename "$p")"
done
echo "1.0" > debian/source/format
dch -l np "OnePlus 8 Pro: QRTR modem on any node, bearer retries, wait for registration"
dpkg-buildpackage -b -uc -us -j"$(nproc)" -d 2>&1 | tail -8
cd ..; cp ./*.deb "$OUT/"
ls -l "$OUT"
