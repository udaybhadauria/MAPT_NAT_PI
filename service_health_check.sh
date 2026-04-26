#!/bin/bash
set -e

echo "🔍 Checking service status..."

restart_needed=0

check_and_restart() {
    local svc="$1"

    if systemctl is-active --quiet "$svc"; then
        echo "✅ $svc is RUNNING"
    else
        echo "❌ $svc FAILED → restarting"
        sudo systemctl restart "$svc"
        restart_needed=1
    fi
}

check_and_restart kea-dhcp4-server
check_and_restart kea-dhcp6-server
check_and_restart radvd
#check_and_restart dibbler-client

echo "---------------------------------------"
echo "🔁 Checking forwarding settings..."

RESTART_NM=0

# IPv4 forwarding
if [[ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]]; then
    echo "⚠️ IPv4 forwarding disabled → enabling"
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null
    RESTART_NM=1
else
    echo "✅ IPv4 forwarding enabled"
fi

# IPv6 forwarding
if [[ "$(sysctl -n net.ipv6.conf.all.forwarding)" != "1" ]]; then
    echo "⚠️ IPv6 forwarding disabled → enabling"
    echo 1 | sudo tee /proc/sys/net/ipv6/conf/all/forwarding >/dev/null
    RESTART_NM=1
else
    echo "✅ IPv6 forwarding enabled"
fi

# ---------------- Restart NetworkManager if needed ----------------
if [[ "$RESTART_NM" -eq 1 ]]; then
    echo "♻️ Forwarding settings changed → restarting NetworkManager"
    sudo systemctl restart NetworkManager
else
    echo "🎉 No forwarding change → NetworkManager restart not required"
fi

echo "---------------------------------------"
echo "🔁 Checking iptables NAT rule..."

################################################################

IFACE="eth0"

ensure_single_masquerade_rule() {
    local cmd="$1"   # iptables or ip6tables
    local iface="$2" # e.g. eth0

    # Count existing rules
    local count
    count=$($cmd -t nat -S POSTROUTING \
        | grep -c -- "-o $iface -j MASQUERADE")

    if [ "$count" -eq 0 ]; then
        echo "➕ Adding MASQUERADE rule ($cmd, $iface)"
        $cmd -t nat -A POSTROUTING -o "$iface" -j MASQUERADE

    elif [ "$count" -gt 1 ]; then
        echo "🧹 Removing duplicate MASQUERADE rules ($cmd, $iface)"
        # Remove ALL
        while $cmd -t nat -C POSTROUTING -o "$iface" -j MASQUERADE 2>/dev/null; do
            $cmd -t nat -D POSTROUTING -o "$iface" -j MASQUERADE
        done
        # Add back ONE
        $cmd -t nat -A POSTROUTING -o "$iface" -j MASQUERADE

    else
        echo "✅ Single MASQUERADE rule already present ($cmd, $iface)"
    fi
}


#IPv4 Rule Validation
ensure_single_masquerade_rule iptables $IFACE

#IPv6 Rule Validation
ensure_single_masquerade_rule ip6tables $IFACE

################################################################

sudo sysctl -w net.ipv6.conf.${IFACE}.accept_ra=0
sudo sysctl -w net.ipv6.conf.${IFACE}.autoconf=1

echo "---------------------------------------"

if [[ $restart_needed -eq 1 ]]; then
    echo "♻️ One or more services were restarted"
else
    echo "🎉 All services healthy"
fi

###############################################################

systemctl is-active --quiet kea-dhcp4-server && echo "✅ kea-dhcp4-server is RUNNING" || echo "❌ kea-dhcp4-server FAILED"
systemctl is-active --quiet kea-dhcp6-server && echo "✅ kea-dhcp6-server is RUNNING" || echo "❌ kea-dhcp6-server FAILED"
systemctl is-active --quiet radvd && echo "✅ radvd is RUNNING" || echo "❌ radvd FAILED"

