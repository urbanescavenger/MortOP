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

# tuic-client's prebuilt binary links libstdc++.so.6 but the feed omits
# +libstdcpp. Declaring it both fixes the -j3 ordering race (provides file may
# not exist yet) and the runtime dependency in the generated package.
if [ -f feeds/small/tuic-client/Makefile ]; then
    sed -i 's/^  DEPENDS:=@USE_MUSL/  DEPENDS:=+libstdcpp @USE_MUSL/' \
        feeds/small/tuic-client/Makefile
fi

# 25.12's tailscale package omits ts_omit_clientupdate but not
# ts_omit_flashappliance. flash-appliance still links clientupdate, so the
# saved AutoUpdate.Check/Apply prefs make every `tailscale up`/`set` fail with
# "Auto-update support is disabled in this build" — including
# --netfilter-mode=off. master already carries the extra tag; backport it.
# openwrt/packages#30886, tailscale/tailscale#21912.
if [ -f feeds/packages/net/tailscale/Makefile ] && \
   ! grep -q 'ts_omit_flashappliance' feeds/packages/net/tailscale/Makefile; then
    sed -i 's/ts_omit_clientupdate,/ts_omit_clientupdate,ts_omit_flashappliance,/' \
        feeds/packages/net/tailscale/Makefile
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

# luci-app-ramfree 的菜单项是 action 型节点(点一下执行 drop_caches 再跳转),
# 挂在 admin/status/release_ram。官方 25.12 的 ucode LuCI 里它会赢下
# admin/status(以及根路径)的 firstchild 解析,于是:
#   GET /cgi-bin/luci/admin/status -> 302 到它自己 -> 浏览器 ERR_TOO_MANY_REDIRECTS
#   GET /cgi-bin/luci/             -> 302 到 admin/status(登录页被打断)
# 挪到 admin/system 下即可:admin/system 的 firstchild 声明了
# "preferred": "system",不会被子节点抢;按钮本身仍可用
# (/admin/system/release_ram -> 302 admin/status)。已在 25.12 镜像上实测。
if [ -f package/luci-app-ramfree/root/usr/share/luci/menu.d/luci-app-ramfree.json ]; then
    sed -i 's#admin/status/release_ram#admin/system/release_ram#' \
        package/luci-app-ramfree/root/usr/share/luci/menu.d/luci-app-ramfree.json
fi

# luci-app-passwall-speedtest: 旁挂 passwall 的 Cloudflare IP 测速(经各 passwall
# 节点本地 SOCKS 测 HTTP HEAD 延迟,把最优 IP 回写 passwall 节点 / hosts / MosDNS)。
# 仓里 Makefile include 的是 feeds/luci/luci.mk,必须放在 package/ 下让 make
# defconfig 扫到;依赖 +curl 由 defconfig 自动拉。
git clone https://github.com/urbanescavenger/luci-app-passwall-speedtest.git package/luci-app-passwall-speedtest
