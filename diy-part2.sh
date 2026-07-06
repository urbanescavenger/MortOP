#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

#sed -i 's/192.168.1.1/192.168.31.160/g'  package/base-files/luci/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# Download prebuilt caddy (l4+webdav modules) from the official Caddy download
# portal. Static linux-amd64 Go binary, runs on OpenWrt musl. Avoids committing
# a 48MB binary to git. Runs after `files/` is moved to openwrt/files/, so the
# downloaded file lands in the rootfs overlay.
CADDY_URL="https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com/mholt/caddy-l4&p=github.com/mholt/caddy-webdav"
mkdir -p files/usr/bin
echo "Downloading caddy from official portal..."
curl -fL "$CADDY_URL" -o files/usr/bin/caddy || { echo "ERROR: caddy download failed" >&2; exit 1; }
chmod 755 files/usr/bin/caddy
# Sanity: must be a valid ELF and reasonably sized (>10MB).
ELF_MAGIC="$(head -c4 files/usr/bin/caddy | od -An -tx1 | tr -d ' \n')"
[ "$ELF_MAGIC" = "7f454c46" ] || { echo "ERROR: caddy download not a valid ELF (got $ELF_MAGIC)" >&2; exit 1; }
SZ="$(wc -c < files/usr/bin/caddy)"
[ "$SZ" -gt 10000000 ] || { echo "ERROR: caddy download too small: ${SZ} bytes" >&2; exit 1; }
echo "caddy ready: ${SZ} bytes"

# tailscale daemon init START 后置 80→99
# (旁路由拓扑下 80 太早,跟 passwall/docker/network 竞态;99 才稳定)。
# 必须放 diy-part2.sh:feeds update 已跑完(workflow 行 163),这里 sed 不会被冲掉。
sed -i 's/^START=80$/START=99/' feeds/packages/net/tailscale/files/tailscale.init
