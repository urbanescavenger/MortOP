#!/bin/sh
# Passwall IPv6 TPROXY + Tailscale coexistence.
#
# 1) Passwall's nftables backend emits `tproxy to :1041` for IPv6 rules, but
#    nft needs the address family: `tproxy ip6 to :1041`. Without it the IPv6
#    packets are not matched and foreign IPv6 leaks direct (and gets reset).
# 2) Tailscale >= 1.96.4 forces net.ipv4.conf.all.src_valid_mark=1 and adds
#    conntrack mark rules, which break passwall's TPROXY policy routing.
#    Disable its netfilter mode and clear src_valid_mark (rc.local does it
#    again late in boot, after tailscaled has started).
# 3) Use TPROXY for TCP so IPv6 TCP traffic is proxied at all.
#
# Runs once at first boot (and after every sysupgrade), before services start.
# Idempotent.

NFT=/usr/share/passwall/nftables.sh
if [ -f "$NFT" ]; then
	sed -i \
		-e 's/\$(REDIRECT \$tcp_port TPROXY)/$(REDIRECT $tcp_port TPROXY6)/g' \
		-e 's/\$(REDIRECT \$udp_port TPROXY)/$(REDIRECT $udp_port TPROXY6)/g' \
		-e 's/\$(REDIRECT \$REDIR_PORT TPROXY)/$(REDIRECT $REDIR_PORT TPROXY6)/g' \
		"$NFT"
fi

if [ -f /etc/config/passwall ]; then
	uci -q set passwall.@global_forwarding[0].tcp_proxy_way='tproxy'
	uci -q set passwall.@global_forwarding[0].ipv6_tproxy='1'
	uci -q commit passwall
fi

if [ -f /etc/config/tailscale ]; then
	uci -q set tailscale.settings.fw_mode='off'
	uci -q commit tailscale
fi

sysctl -w net.ipv4.conf.all.src_valid_mark=0 2>/dev/null

exit 0
