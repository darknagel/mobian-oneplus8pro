#!/bin/bash
# Run on the phone as the mobian user (build deps installed beforehand as root).
# Rebuild a Debian source package with our patches, optionally on a newer
# upstream tarball, keeping Debian's packaging.
#   build-patched-deb.sh SRCPKG LOCALVER [ORIG_URL NEWVER]
# Patches: ~/build/patches/SRCPKG/*.patch (applied with -p1 in name order).
# Result:  ~/build/out/*.deb
set -euo pipefail
PKG=$1 LOCAL=$2 URL=${3:-} NEWVER=${4:-}
B=$HOME/build
OUT=$B/out
mkdir -p "$OUT"
export DEBEMAIL=noreply@localhost DEBFULLNAME="local build" DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)"

W=$B/work-$PKG
rm -rf "$W"; mkdir -p "$W"; cd "$W"
apt-get source -qq "$PKG" >/dev/null
DEB=$(find . -maxdepth 1 -mindepth 1 -type d | head -1)

if [ -n "$URL" ]; then
  # new upstream version: unpack it and move Debian's packaging over
  curl -sL -o "${PKG}_${NEWVER}.orig.tar.gz" "$URL"
  mkdir new; tar xzf "${PKG}_${NEWVER}.orig.tar.gz" -C new --strip-components=1
  cp -a "$DEB/debian" new/
  SRC=$W/new
  cd "$SRC"
  mkdir -p debian/patches; : > debian/patches/series.new
  if [ -f debian/patches/series ]; then
    while read -r p; do
      case "$p" in ''|\#*) continue ;; esac
      if patch -p1 --dry-run -s -f < "debian/patches/$p" >/dev/null 2>&1; then
        patch -p1 -s < "debian/patches/$p"; echo "$p" >> debian/patches/series.new; echo "debian patch ok: $p"
      else
        echo "debian patch dropped: $p"
      fi
    done < debian/patches/series
  fi
  mv debian/patches/series.new debian/patches/series
  VER="${NEWVER}-0${LOCAL}"
else
  # same upstream version: Debian's patches are already applied by apt-get source
  SRC=$W/$DEB
  cd "$SRC"
  mkdir -p debian/patches
  VER=""
fi

for p in "$B/patches/$PKG"/*.patch; do
  [ -e "$p" ] || continue
  patch -p1 -s < "$p"
  cp "$p" debian/patches/; basename "$p" >> debian/patches/series
  echo "our patch ok: $(basename "$p")"
done
# optional per-package packaging tweaks, run in the source tree
if [ -f "$B/patches/$PKG/hook.sh" ]; then
  sh "$B/patches/$PKG/hook.sh"; echo "hook ok"
fi
# patches are in the tree already; format 1.0 keeps dpkg-source from applying them again
echo "1.0" > debian/source/format
if [ -n "$VER" ]; then
  dch -v "$VER" -D unstable "OnePlus 8 Pro: upstream $NEWVER with the port's patches"
else
  dch -l "$LOCAL" "OnePlus 8 Pro: the port's patches"
fi
sed -i 's/^export DPKG_GENSYMBOLS_CHECK_LEVEL=4/export DPKG_GENSYMBOLS_CHECK_LEVEL=0/' debian/rules
dpkg-buildpackage -B -uc -us -j"$(nproc)" -d 2>&1 | tail -12
cd "$(dirname "$SRC")"
cp ./*.deb "$OUT/"
ls -1 ./*.deb
