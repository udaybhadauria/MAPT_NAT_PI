#!/bin/bash

# Get local interface (enx* or eth1 — first match)
IFACE=$(ifconfig | awk -F: '/^(enx|eth1)/ {print $1; exit}')

LOCAL_MAC=$(cat /sys/class/net/$IFACE/address)
#LOCAL_MAC="a0:ce:c8:c2:ae:24"

# ===== Fetch upstream link-local =====
UPSTREAM_FE80=$(ip -6 neigh show dev "$IFACE" \
    | grep -i 'fe80' \
    | grep -i 'lladdr' \
    | grep -vi "$LOCAL_MAC" \
    | awk '{print $1}')

# ===== Output =====
if [ -n "$UPSTREAM_FE80" ]; then
    echo "Upstream Link-Local Found:"
    for ip in $UPSTREAM_FE80; do
        echo "${ip}%${IFACE}"
    done
else
    echo "No upstream link-local address found"
fi

ping6 -c 4 "${ip}%${IFACE}"
if [ $? -ne 0 ]; then
    echo "❌ Neighbor ${ip}%${IFACE} not reachable — aborting"
    exit 1
fi
echo "✅ Neighbor reachable, proceeding..."
