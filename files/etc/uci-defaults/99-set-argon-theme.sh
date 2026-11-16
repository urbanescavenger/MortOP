#!/bin/sh
# Default LuCI theme: Argon. The luci package defaults to openwrt2020; the
# theme package registers /luci-static/argon but does not select it.
uci -q set luci.main.mediaurlbase='/luci-static/argon'
uci -q commit luci
exit 0
