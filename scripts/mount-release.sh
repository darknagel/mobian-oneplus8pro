#!/bin/bash
# Mount the root partition of the pmOS port's release image (v2026.11.22,
# oneplus-instantnoodlep-rootfs.img unpacked with simg2img) read-only and list
# the device-specific packages and files. build-support-deb.sh reads from it.
#   mount-release.sh /path/to/rootfs.raw
set -euo pipefail
IMG=${1:?usage: mount-release.sh RAW_ROOTFS_IMAGE}
MNT=${WORK:-$HOME/mobian}/relmnt
mkdir -p "$MNT"
mountpoint -q "$MNT" || {
  sudo losetup -D
  LOOP=$(sudo losetup -b 4096 -fP --show -r "$IMG")
  sudo mount -o ro "${LOOP}p2" "$MNT"
}
DB=$MNT/lib/apk/db/installed
# print package -> files for device specific packages
awk -v RS= '
  /\nP:(device-|firmware-|alsa-ucm-conf-oneplus|hexagonrpcd|libssc|81voltd|qsee|usb-signaller|soc-qcom|pd-mapper|tqftpserv|rmtfs|qrtr|bootmac|iio-sensor)/ {
    n=split($0,L,"\n"); pkg=""; dir="";
    for(i=1;i<=n;i++){ if(L[i]~/^P:/){pkg=substr(L[i],3); print "## " pkg}
      else if(L[i]~/^V:/){print "   ver " substr(L[i],3)}
      else if(L[i]~/^F:/){dir=substr(L[i],3)}
      else if(L[i]~/^R:/){print "   " dir "/" substr(L[i],3)} }
  }' "$DB"
echo "== enabled units"
ls "$MNT"/etc/systemd/system/*.wants/ 2>/dev/null
echo "== /usr/local"
find "$MNT"/usr/local -type f
