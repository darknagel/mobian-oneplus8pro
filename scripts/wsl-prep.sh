#!/bin/bash
# Prepare WSL (no systemd) for debos image builds: clean leftovers, qemu binfmt, udevd.
# Run as root:  wsl-prep.sh /path/to/mobian-recipes
RECIPES=${1:?usage: wsl-prep.sh MOBIAN_RECIPES_DIR}
for l in $(losetup -a | grep mobian-wip | cut -d: -f1); do losetup -d "$l"; done
for m in $(grep -o "$RECIPES/.debos-[^ ]*" /proc/mounts | sort -r); do umount -l "$m"; done
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || grep -v '^#' /usr/lib/binfmt.d/qemu-aarch64.conf > /proc/sys/fs/binfmt_misc/register
pgrep -x systemd-udevd >/dev/null || /usr/lib/systemd/systemd-udevd --daemon
sleep 1
udevadm trigger --action=add --subsystem-match=block
timeout 30 udevadm settle && echo "udev settle ok"
pgrep -a systemd-udevd
losetup -a
ls /dev/disk/by-uuid | head -3
