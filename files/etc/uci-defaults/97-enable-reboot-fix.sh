#!/bin/sh
# Enable the reboot-fix shutdown script on first boot (creates K99/S99 symlinks).
# uci-defaults runs once on first boot and is deleted after success; the symlinks
# persist, so the cleanup runs on every shutdown. Re-runs on each reflash.
/etc/init.d/reboot-fix enable 2>/dev/null
exit 0