#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# This branch targets official OpenWrt 25.12 (kernel 6.12) instead of lede.
#

# Official feeds + kenzok8 feeds are configured in feeds.conf.default.
./scripts/feeds update -a

# kenzok8's design theme uses PKG_VERSION 5.8.0-20240106. Official 25.12 builds
# apk packages, and apk's version parser rejects the inner hyphen
# ("package version is invalid"). Switch it to Alpine's ~ separator.
if [ -f feeds/kenzo/luci-theme-design/Makefile ]; then
    sed -i 's/^PKG_VERSION:=5\.8\.0-20240106$/PKG_VERSION:=5.8.0~20240106/' \
        feeds/kenzo/luci-theme-design/Makefile
fi

# tuic-client's prebuilt binary links libstdc++.so.6 but the feed omits
# +libstdcpp. Declaring it both fixes the -j3 ordering race (provides file may
# not exist yet) and the runtime dependency in the generated package.
if [ -f feeds/small/tuic-client/Makefile ]; then
    sed -i 's/^  DEPENDS:=@USE_MUSL/  DEPENDS:=+libstdcpp @USE_MUSL/' \
        feeds/small/tuic-client/Makefile
fi

# Prune kenzok8 duplicates of packages official 25.12 already ships. Must run
# between update and install: feeds install links whatever is present, and a
# duplicate name makes it ambiguous which one ends up in the image.
rm -rf feeds/kenzo/luci-app-adguardhome feeds/kenzo/adguardhome \
       feeds/kenzo/luci-app-dockerman \
       feeds/kenzo/luci-app-smartdns feeds/kenzo/smartdns

./scripts/feeds install -a

# Apps 158 runs that official 25.12 does not ship. Take only the LuCI
# front-ends from ImmortalWrt's openwrt-25.12 branch (same LuCI generation,
# so they build against official's luci.mk). Underlying daemons (parted,
# netdata, nfs-kernel-server, zerotier) all come from official feeds.
IMM_LUCI=/tmp/iw-luci
rm -rf $IMM_LUCI
git clone --depth 1 --filter=blob:none --sparse -b openwrt-25.12 \
    https://github.com/immortalwrt/luci.git $IMM_LUCI
git -C $IMM_LUCI sparse-checkout set \
    applications/luci-app-diskman \
    applications/luci-app-netdata \
    applications/luci-app-nfs \
    applications/luci-app-ramfree \
    applications/luci-app-zerotier
cp -a $IMM_LUCI/applications/luci-app-diskman \
      $IMM_LUCI/applications/luci-app-netdata \
      $IMM_LUCI/applications/luci-app-nfs \
      $IMM_LUCI/applications/luci-app-ramfree \
      $IMM_LUCI/applications/luci-app-zerotier \
      package/
rm -rf $IMM_LUCI

# These Makefiles say `include ../../luci.mk`, which only resolves inside the
# luci feed tree (feeds/luci/applications/<app>). Repoint them at the official
# luci.mk now that they live under package/.
for app in diskman netdata nfs ramfree zerotier; do
    sed -i 's#^include \.\./\.\./luci\.mk#include $(TOPDIR)/feeds/luci/luci.mk#' \
        package/luci-app-$app/Makefile
done

# luci-app-passwall-speedtest: 旁挂 passwall 的 Cloudflare IP 测速(经各 passwall
# 节点本地 SOCKS 测 HTTP HEAD 延迟,把最优 IP 回写 passwall 节点 / hosts / MosDNS)。
# 仓里 Makefile include 的是 feeds/luci/luci.mk,必须放在 package/ 下让 make
# defconfig 扫到;依赖 +curl 由 defconfig 自动拉。
git clone https://github.com/urbanescavenger/luci-app-passwall-speedtest.git package/luci-app-passwall-speedtest
