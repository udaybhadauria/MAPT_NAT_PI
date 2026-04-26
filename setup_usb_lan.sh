#!/bin/bash
set -e

# ------------------------------
# Detect LAN interface dynamically
# ------------------------------
# Interface detection
IFACE="$(./local_interface.sh | tr -d '[:space:]' | xargs)"
[ -z "$IFACE" ] && { echo "ERROR: No interface detected"; exit 1; }

echo "Detected LAN interface: $IFACE"

# ------------------------------
# Read IP values from default_data.json
# ------------------------------
if [ ! -f default_data.json ]; then
    echo "❌ default_data.json not found in current directory"
    exit 1
fi

# Use jq to extract values
LAN_IPV4=$(jq -r '.ipv4.router + "/24"' default_data.json)
LAN_IPV6=$(jq -r '.ipv6.lan_prefix' default_data.json | sed 's|/64|/64|')  # keep /64

echo "Using IPv4: $LAN_IPV4"
echo "Using IPv6: $LAN_IPV6"

# ------------------------------
# Delete old NM connection if exists
# ------------------------------
sudo nmcli connection delete LAN_USB 2>/dev/null || true

# ------------------------------
# Add new connection
# ------------------------------
sudo nmcli connection add type ethernet con-name LAN_USB ifname "$IFACE" \
ipv4.addresses "$LAN_IPV4" ipv4.method manual \
ipv6.addresses "$LAN_IPV6" ipv6.method manual

# ------------------------------
# Bring interface up
# ------------------------------
sudo nmcli connection up LAN_USB

echo "✅ LAN interface $IFACE configured with static IPs from default_data.json"
nmcli device status | grep "$IFACE"
