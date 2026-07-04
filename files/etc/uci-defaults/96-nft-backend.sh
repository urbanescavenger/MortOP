#!/bin/sh
# Force iptables/ip6tables backend to nft (xtables-nft-multi) so fw3/docker/
# miniupnpd/passwall stop writing legacy ip_tables rules — clears the LuCI
# "检测到旧版 iptables 规则 / legacy iptables rules detected" warning.
#
# Runs at first boot, before network/firewall services start. Idempotent.
# No-op if xtables-nft-multi is absent (build didn't include iptables-nft, e.g.
# legacy iptables won the opkg transitive-dep conflict — see openwrt#22452);
# in that case the warning persists but nothing breaks.
#
# xtables-nft-multi dispatches on argv[0] basename, so the symlink must keep the
# legacy command name (iptables/iptables-save/...) and point at xtables-nft-multi
# — exactly how OpenWrt's ALTERNATIVES sets it up.

NFT=/usr/sbin/xtables-nft-multi
[ -x "$NFT" ] || { echo "nft-backend: xtables-nft-multi missing; cannot switch"; exit 0; }

# Repoint the xtables command family to the nft multi-binary.
for cmd in iptables iptables-save iptables-restore ip6tables ip6tables-save ip6tables-restore; do
	ln -sf xtables-nft-multi "/usr/sbin/$cmd" 2>/dev/null
done

# Flush any legacy rules a prior boot left behind so this boot starts clean via nft.
for t in filter nat mangle raw; do
	iptables-legacy -t "$t" -F 2>/dev/null
	iptables-legacy -t "$t" -X 2>/dev/null
done

exit 0