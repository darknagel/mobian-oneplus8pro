#!/bin/sh
# Run as root on the phone: append kernel parameters to the boot image of the
# active slot (keeps kernel, initrd, dtb and addresses), optionally remove some.
# Usage: $0 "param ..." ["remove ..."]
set -eu
ADD="$1"
DEL="${2:-}"
SLOT=$(qbootctl -x 2>/dev/null | tail -1)
PART=/dev/disk/by-partlabel/boot${SLOT}
T=$(mktemp -d)
dd if="$PART" of="$T/boot.img" bs=1M status=none
P=$(unpack_bootimg --format mkbootimg --out "$T/u" --boot_img "$T/boot.img")
CMD=$(echo "$P" | sed "s/.*--cmdline '\(.*\)'/\1/")
CLEAN=$(echo "$P" | sed -e "s/ --cmdline '.*'//" -e "s/ --board '.*'//")
for d in $DEL; do
	CMD=$(echo " $CMD " | sed "s/ $d / /g; s/^ *//; s/ *$//")
done
for a in $ADD; do
	case " $CMD " in *" $a "*) ;; *) CMD="$CMD $a" ;; esac
done
# shellcheck disable=SC2086
mkbootimg -o "$T/new.img" $CLEAN --cmdline "$CMD"
cp "$T/boot.img" /var/backups/boot${SLOT}-before-cmdline.img
dd if="$T/new.img" of="$PART" bs=1M status=none
echo "boot${SLOT} cmdline: $CMD"
rm -rf "$T"
