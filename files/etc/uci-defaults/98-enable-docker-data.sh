#!/bin/sh
# Enable the /opt/docker auto-mount init on first boot. The data partition itself
# is created+formatted+mounted by 99-data-partition.sh (runs next); the
# docker-data init's boot() hook then re-mounts it on every subsequent boot,
# before dockerd starts. Idempotent; never breaks boot.
mkdir -p /opt/docker
/etc/init.d/docker-data enable 2>/dev/null
exit 0