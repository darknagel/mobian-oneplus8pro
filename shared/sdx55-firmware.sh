#!/bin/sh
# Copy the SDX55 modem firmware and data from this phone's own partitions.
# Runs at boot before udev loads the modem driver (sdx55-firmware.service)
# and does nothing once the copies exist.
#
#  - firmware: modem_<slot>/image/sdx55m, the slot the bootloader started.
#    It must be the same version as the RF configuration the modem reads
#    from that partition at run time (sdx55-rfsd); a different
#    version leaves the RF unconfigured and the modem stays offline.
#  - Sahara image 16/17 (modem EFS) from mdm1m9kefs1/2, 20 (OnePlus NV
#    backup) from mdm1oemnvbktmp, 34 (DDR training) from mdmddr.
# These copies hold the phone's calibration and identifiers: never share them.
FW=${SDX55_FW:-/lib/firmware/postmarketos/qcom/sdx55m}
[ -e $FW/qdsp6sw.mbn ] && [ -e $FW/efs3.bin ] && exit 0

# /dev/disk/by-partlabel does not exist yet this early
part() {
	for u in /sys/class/block/*/uevent; do
		grep -qx "PARTNAME=$1" "$u" && echo /dev/$(sed -n 's/^DEVNAME=//p' "$u") && return
	done
	return 1
}

# The slot the bootloader started; all firmware services read the same one
android_slot() {
	for arg in $(cat /proc/cmdline); do
		case "$arg" in
		androidboot.slot_suffix=_a) echo a; return 0 ;;
		androidboot.slot_suffix=_b) echo b; return 0 ;;
		esac
	done
	# The bootloader leaves out slot_suffix for some boot images (Mobian);
	# the GPT slot flags still tell the active slot
	s=$(qbootctl -c 2>/dev/null | sed -n 's/^Current slot: _\([ab]\)$/\1/p')
	[ -n "$s" ] && { echo "$s"; return 0; }
	return 1
}

set -e
slot=$(android_slot) || { echo "sdx55-firmware: cannot determine the Android firmware slot" >&2; exit 1; }
mkdir -p $FW
MNT=$(mktemp -d)
mount -o ro "$(part modem_$slot)" $MNT
for f in $MNT/image/sdx55m/*; do
	case ${f##*/} in efs*|mdmddr.mbn) continue ;; esac
	cp "$f" $FW/
done
umount $MNT
rmdir $MNT

[ -e $FW/efs1.bin ] || dd if="$(part mdm1m9kefs1)" of=$FW/efs1.bin status=none
[ -e $FW/efs2.bin ] || dd if="$(part mdm1m9kefs2)" of=$FW/efs2.bin status=none
[ -e $FW/efs3.bin ] || dd if="$(part mdm1oemnvbktmp)" of=$FW/efs3.bin status=none
[ -e $FW/mdmddr.mbn ] || dd if="$(part mdmddr)" of=$FW/mdmddr.mbn status=none
chmod 600 $FW/*
echo "sdx55-firmware: copied modem firmware and data from this phone"
