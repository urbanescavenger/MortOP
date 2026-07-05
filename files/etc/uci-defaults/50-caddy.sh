#!/bin/sh
# Ensure caddy binary is executable, prepare cert dir, enable service on first boot.
chmod 755 /usr/bin/caddy
mkdir -p /etc/caddy/cert
/etc/init.d/caddy enable 2>/dev/null
exit 0
