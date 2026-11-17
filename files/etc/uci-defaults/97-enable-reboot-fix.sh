#!/bin/sh
# Enable the reboot-fix shutdown script on first boot (creates S99/K01 symlinks).
# uci-defaults runs once on first boot and is deleted after success; the symlinks
# persist, so the cleanup runs on every shutdown. Re-runs on each reflash.
/etc/init.d/reboot-fix enable
if [ ! -e /etc/rc.d/S99reboot-fix ] || [ ! -e /etc/rc.d/K01reboot-fix ]; then
	logger -t reboot-fix-enable -p daemon.err "failed to enable reboot-fix (missing rc.d symlink)"
fi
exit 0