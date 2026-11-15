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

# Default LAN IP / hostname for the 160 bypass router. OpenWrt has no Kconfig
# symbol for these; config_generate hardcodes 192.168.1.1 and "OpenWrt".
# NOTE: config_generate does not emit a gateway/DNS, so 160 still needs
#   uci set network.lan.gateway='192.168.31.158'
#   uci set network.lan.dns='192.168.31.158'
# once after flashing (or a uci-defaults script, if we later want it baked in).
sed -i 's/192\.168\.1\.1/192.168.31.160/g' package/base-files/files/bin/config_generate
sed -i 's/OpenWrt/MortOP-160/g' package/base-files/files/bin/config_generate

# Download prebuilt caddy (l4+webdav modules) from the official Caddy download
# portal. Static linux-amd64 Go binary, runs on OpenWrt musl. Avoids committing
# a 48MB binary to git. Runs after `files/` is moved to openwrt/files/, so the
# downloaded file lands in the rootfs overlay.
# caddy-l4 is pinned to v0.1.2: v0.1.3 (2026-11-12) requires Go 1.26 / Caddy
# v2.11.7, and the portal's builder returns HTTP 400 for it combined with any
# other module (e.g. webdav). Bump the pin once the portal can build it.
CADDY_URL="https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com/mholt/caddy-l4@v0.1.2&p=github.com/mholt/caddy-webdav"
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
