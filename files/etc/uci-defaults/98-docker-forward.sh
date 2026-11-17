#!/bin/sh
# Allow every Docker network (172.16.0.0/12) to forward to WAN without having
# to add each new br-<id> to firewall.docker.device. New Docker networks get
# a new bridge name, so a static zone device list misses them and containers
# on the new network cannot reach the internet.
#
# Community consensus (openwrt/packages#26500, #29963) is to avoid per-bridge
# uciadd hooks and match the bridge/subnet generically instead. This rule is
# interface-independent and survives new networks.
#
# Idempotent: skips if a rule with this name already exists.

if [ -f /etc/config/firewall ] && ! uci show firewall 2>/dev/null | grep -q "name='Allow-Docker-Forward'"; then
	uci set firewall.docker_forward=rule
	uci set firewall.docker_forward.name='Allow-Docker-Forward'
	uci set firewall.docker_forward.src='*'
	uci set firewall.docker_forward.src_ip='172.16.0.0/12'
	uci set firewall.docker_forward.dest='wan'
	uci set firewall.docker_forward.target='ACCEPT'
	uci -q commit firewall
fi

exit 0
