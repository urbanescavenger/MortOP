#!/bin/sh
# First-boot: grow the rootfs partition to fill the disk, then resize ext4.
# Runs once via /etc/uci-defaults on first boot; deleted after success.
# Safe: never fails the boot — always exits 0; idempotent if re-run.

log() { echo "grow-rootfs: $*"; }

# 1) Resolve the underlying root block device (x86: usually /dev/sda2).
root_dev=$(mount | awk '$3=="/" && $1!="/dev/root"{print $1; exit}')
[ -z "$root_dev" ] && root_dev=$(readlink -f /dev/root 2>/dev/null)
if [ ! -b "$root_dev" ]; then
	log "no root block device found; nothing to do"
	exit 0
fi

# 2) Derive whole-disk device + partition number.
case "$root_dev" in
  */nvme*|*/mmcblk*)
	disk="${root_dev%p[0-9]*}"
	partno="${root_dev##*p}"
	;;
  *)
	disk="${root_dev%[0-9]*}"
	partno="${root_dev#$disk}"
	;;
esac
if [ ! -b "$disk" ]; then
	log "disk $disk not a block device; nothing to do"
	exit 0
fi

# 3) Relocate GPT backup header to actual disk end (no-op on MBR).
#    Needed because dd'ing a small image onto a larger disk leaves the
#    backup GPT mid-disk, which makes parted resizepart fail.
if command -v sgdisk >/dev/null 2>&1; then
	sgdisk -e "$disk" >/dev/null 2>&1 || log "sgdisk -e failed (may be MBR)"
fi

# 4) Grow the root partition to 100%.
if ! parted -s -m "$disk" resizepart "$partno" 100% >/dev/null 2>&1; then
	log "parted resizepart failed (already full or unsupported table)"
fi

# 5) Re-read the partition table so the kernel sees the new size.
partprobe "$disk" 2>/dev/null
sleep 1

# 6) Grow the ext4 filesystem online to fill the (now larger) partition.
if command -v resize2fs >/dev/null 2>&1; then
	resize2fs "$root_dev" >/dev/null 2>&1 || log "resize2fs failed"
else
	log "resize2fs not installed; cannot grow fs"
fi

log "done (root=$root_dev disk=$disk part=$partno)"
exit 0