#!/bin/sh
# First-boot: fix the GPT backup header, then carve a DATA partition from the
# remaining disk space and format it ext4. The root partition is left untouched.
#
# Why not grow the rootfs ext4: lede's image-built rootfs is a journal-less ext4
# (no resize_inode), so online resize2fs fails with EINVAL. Carving a separate
# data partition sidesteps that entirely and gives a mountable volume for the
# rest of the disk. Mount it manually (e.g. /mnt/data) after first boot.
#
# Runs once via /etc/uci-defaults on first boot; deleted after. Always exits 0
# (never breaks boot). Idempotent: skips if the data partition already exists.

log() { echo "data-part: $*"; }
exec > /tmp/data-part.log 2>&1

# 1) Resolve root device, whole-disk device, root partition number.
root_dev=$(mount | awk '$3=="/" && $1!="/dev/root"{print $1; exit}')
[ -z "$root_dev" ] && root_dev=$(readlink -f /dev/root 2>/dev/null)
[ -b "$root_dev" ] || { log "no root block device; exit"; exit 0; }
case "$root_dev" in
  */nvme*|*/mmcblk*) disk="${root_dev%p[0-9]*}"; partno="${root_dev##*p}" ;;
  *) disk="${root_dev%[0-9]*}"; partno="${root_dev#$disk}" ;;
esac
[ -b "$disk" ] || { log "disk $disk not a block device; exit"; exit 0; }
dbn=$(basename "$disk")
case "$root_dev" in
  */nvme*|*/mmcblk*) data_dev="${disk}p$((partno+1))" ;;
  *) data_dev="${disk}$((partno+1))" ;;
esac

command -v parted >/dev/null 2>&1 || { log "parted not installed; exit"; exit 0; }

# 2) Idempotency: data partition already exists -> done.
[ -b "$data_dev" ] && { log "$data_dev already exists; skip"; exit 0; }

# 3) Fix GPT backup header. dd'ing a small image onto a larger disk leaves the
#    backup GPT mid-disk; fdisk 'w' auto-corrects PMBR + backup GPT placement.
#    Safe on a mounted root disk (only the backup-header sector is rewritten).
if command -v fdisk >/dev/null 2>&1; then
  printf 'w\n' | fdisk "$disk" >/dev/null 2>&1 || log "fdisk GPT fix returned nonzero (may still be ok)"
  partprobe "$disk" 2>/dev/null
fi

# 4) Compute free space after the root partition; bail if < 1 GiB.
root_end=$(parted -s -m "$disk" unit s print 2>/dev/null | awk -F: -v p="$partno" '$1==p{sub(/s$/,"",$3); print $3; exit}')
[ -n "$root_end" ] || { log "can't determine root partition end; exit"; exit 0; }
disk_sectors=$(cat /sys/block/"$dbn"/size 2>/dev/null)
[ -n "$disk_sectors" ] || { log "can't read disk size; exit"; exit 0; }
free_sectors=$((disk_sectors - root_end - 1))
[ "$free_sectors" -lt 2097152 ] && { log "free space < 1 GiB ($free_sectors sectors); nothing to carve; exit"; exit 0; }

# 5) Create the data partition (root_end+1 .. 100%) and format it.
start=$((root_end + 1))
parted -s "$disk" mkpart data "${start}s" 100% >/dev/null 2>&1 || log "mkpart returned nonzero"
partprobe "$disk" 2>/dev/null
sleep 1
[ -b "$data_dev" ] || { log "$data_dev not created; exit"; exit 0; }

if command -v mkfs.ext4 >/dev/null 2>&1; then
  mkfs.ext4 -F -L data "$data_dev" >/dev/null 2>&1 || { log "mkfs.ext4 failed; exit"; exit 0; }
else
  log "mkfs.ext4 not installed; partition created but unformatted"
fi

log "done: data partition $data_dev created+formatted (root $root_dev untouched)"
exit 0
