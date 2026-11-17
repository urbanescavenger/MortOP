#!/bin/sh
# Passwall IPv6 TPROXY + Tailscale coexistence.
#
# 1) Passwall's nftables backend emits `tproxy to :1041` for IPv6 rules, but
#    nft needs the address family: `tproxy ip6 to :1041`.
# 2) Passwall's default TCP rule redirects every port not listed in
#    tcp_no_redir_ports. Ollama's published port 11434 must stay out, or
#    passwall grabs it before Docker's DNAT does.
# 3) Use TPROXY for TCP so IPv6 TCP traffic is proxied at all.
# 4) Tailscale sets net.ipv4.conf.all.src_valid_mark=1 on every start, which
#    breaks passwall's TPROXY policy routing. Reset it from the tailscale init
#    script after start (and again in rc.local at boot).
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

	# Keep ollama's published port out of the transparent proxy.
	for opt in tcp_no_redir_ports udp_no_redir_ports; do
		v="$(uci -q get passwall.@global_forwarding[0].$opt)"
		case ",$v," in
			*,11434,*) ;;
			*) [ -n "$v" ] && uci -q set passwall.@global_forwarding[0].$opt="$v,11434" || uci -q set passwall.@global_forwarding[0].$opt='11434' ;;
		esac
	done
	uci -q commit passwall
fi

# tailscaled sets src_valid_mark=1 on every start; reset it after it is up.
TS_INIT=/etc/init.d/tailscale
if [ -f "$TS_INIT" ] && ! grep -q 'passwall TPROXY needs src_valid_mark=0' "$TS_INIT"; then
	sed -i '/^[[:space:]]*procd_close_instance[[:space:]]*$/i\  ( for i in 1 2 3 4 5 6 7 8; do sleep 2; sysctl -w net.ipv4.conf.all.src_valid_mark=0 >/dev/null 2>/dev/null; done ) & # passwall TPROXY needs src_valid_mark=0' "$TS_INIT"
fi

sysctl -w net.ipv4.conf.all.src_valid_mark=0 2>/dev/null

exit 0
