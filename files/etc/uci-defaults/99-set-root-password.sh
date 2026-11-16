#!/bin/sh
# Default root password for the intranet (user request: root/1234).
# The firmware releases are public, so this is a known credential; change it
# if the device is ever exposed beyond the LAN.
HASH='$5$mortop$GcBC83O/12kCR0YONoXd88EPHb5YBJMrsjEj4SbWlfC'
sed -i "s|^root:[^:]*:|root:$HASH:|" /etc/shadow
exit 0
