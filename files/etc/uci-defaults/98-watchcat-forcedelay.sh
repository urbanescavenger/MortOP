#!/bin/sh
# Enforce a forcedelay above the clean shutdown time even if the package's
# /etc/config/watchcat was installed after the files/ overlay.
uci -q set watchcat.@watchcat[0].forcedelay='180'
uci -q commit watchcat
exit 0
