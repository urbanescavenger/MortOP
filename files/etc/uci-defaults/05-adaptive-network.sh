#!/bin/sh
# Adaptive first-boot network setup for x86 mini-PCs.
#
# OpenWrt's x86 board.d/02_network only assigns lan/wan for named boards; a
# generic dual-NIC box gets LAN on eth0 and no WAN. Fill that gap on a fresh
# flash:
#   >=2 physical NICs -> main router: LAN br-lan/eth0 192.168.31.160/24 with
#                        DHCP server, WAN eth1 DHCP (optical modem) + wan6
#    1 physical NIC  -> bypass router: LAN br-lan/eth0 192.168.31.160/24,
#                        gateway/DNS 192.168.31.158, local DHCP server off
#
# Only acts on the generated default config (no WAN, LAN still
# 192.168.31.160 or 192.168.1.1). A keep-settings upgrade or restored backup
# with an existing WAN/gateway is left untouched.
#
# Caveat: both roles use 192.168.31.160 as the LAN address. A dual-NIC main
# router and a single-NIC bypass must not both sit on the same L2 with .160;
# change one of them (or its gateway) if they ever coexist.

[ -f /etc/config/network ] || exit 0

# Already configured (keep settings / restored backup): do not touch.
[ -n "$(uci -q get network.wan)" ] && exit 0
[ -n "$(uci -q get network.lan.gateway)" ] && exit 0

lan_ip="$(uci -q get network.lan.ipaddr)"
case "$lan_ip" in
	192.168.31.160*|192.168.1.1*) ;;
	*) exit 0 ;;
esac

n=0
for d in /sys/class/net/eth*; do
	[ -e "$d/device" ] || continue
	n=$((n + 1))
done

uci -q set network.lan.proto='static'
uci -q set network.lan.ipaddr='192.168.31.160/24'
uci -q set network.lan.device='br-lan'
uci -q delete network.lan.gateway
uci -q delete network.lan.dns

if [ "$n" -ge 2 ]; then
	# Main router: WAN on the second physical NIC, DHCP from the optical modem.
	uci -q set network.wan=interface
	uci -q set network.wan.device='eth1'
	uci -q set network.wan.proto='dhcp'
	uci -q set network.wan6=interface
	uci -q set network.wan6.device='eth1'
	uci -q set network.wan6.proto='dhcpv6'
	uci -q commit network
	logger -t adaptive-network "dual NIC: main router, WAN=eth1 DHCP, LAN=192.168.31.160/24"
	exit 0
fi

if [ "$n" -eq 1 ]; then
	# Bypass router: one NIC, upstream is the main router.
	uci -q set network.lan.gateway='192.168.31.158'
	uci -q set network.lan.dns='192.168.31.158'
	uci -q commit network
	uci -q set dhcp.lan.ignore='1'
	uci -q commit dhcp
	logger -t adaptive-network "single NIC: bypass router, LAN=192.168.31.160/24 gw=192.168.31.158, DHCP server off"
	exit 0
fi

logger -t adaptive-network "no physical eth* NIC found; leaving network config untouched"
exit 0
