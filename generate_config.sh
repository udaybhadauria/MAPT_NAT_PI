#!/bin/bash
set -e

############################
# NAT_PI VARIABLES (EDIT ME)
############################

LAN_IF="${LAN_IF:-}"
if [[ -z "$LAN_IF" ]]; then
  LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | awk '
    $1 != "lo" && $1 != "eth0" &&
    $1 !~ /^docker/ && $1 !~ /^veth/ && $1 !~ /^br-/ && $1 !~ /^virbr/ &&
    $1 !~ /^wl/ {print; exit}
  ')
fi

if [[ -z "$LAN_IF" ]]; then
  echo "❌ Unable to auto-detect LAN interface. Export LAN_IF=<iface> and rerun."
  echo "Available interfaces:"
  ip -o link show | awk -F': ' '{print " - " $2}'
  exit 1
fi

if ! ip link show "$LAN_IF" >/dev/null 2>&1; then
  echo "❌ LAN interface '$LAN_IF' does not exist"
  exit 1
fi

# IPv4
IPV4_SUBNET="192.168.12.0/24"
IPV4_ADDR="192.168.12.1/24"
IPV4_POOL_START="192.168.12.100"
IPV4_POOL_END="192.168.12.200"
IPV4_ROUTER="192.168.12.1"

# IPv6
IPV6_SUBNET="fd72:3456:789a::/64"
IPV6_ADDR="fd72:3456:789a::1/64"
IPV6_POOL_START="fd72:3456:789a::150"
IPV6_POOL_END="fd72:3456:789a::200"
RADVD_PREFIX="fd72:3456:789a::/64"

# DNS
DNS4="8.8.8.8,9.9.9.9"
DNS6="2001:4860:4860::8888,2001:4860:4860::8844"

# Lifetimes
LIFETIME=604800
RENEW4=300
REBIND4=600
RENEW6=518400
REBIND6=604800

############################
# DO NOT EDIT BELOW
############################

mkdir -p /etc/kea /var/log/kea

# ---------- KEA DHCPv4 ----------
cat > /etc/kea/kea-dhcp4.conf <<EOF
{
  "Dhcp4": {
    "interfaces-config": {
      "interfaces": ["$LAN_IF"]
    },
    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/dhcp4.leases"
    },
    "subnet4": [
      {
        "id": 1,
        "subnet": "$IPV4_SUBNET",
        "interface": "$LAN_IF",
        "pools": [
          { "pool": "$IPV4_POOL_START - $IPV4_POOL_END" }
        ],
        "option-data": [
          { "name": "routers", "data": "$IPV4_ROUTER" },
          { "name": "domain-name-servers", "data": "$DNS4" }
        ]
      }
    ],
    "valid-lifetime": $LIFETIME,
    "renew-timer": $RENEW4,
    "rebind-timer": $REBIND4,
    "loggers": [
      {
        "name": "kea-dhcp4",
        "output_options": [{ "output": "/var/log/kea/kea-dhcp4.log" }],
        "severity": "INFO"
      }
    ]
  }
}
EOF

# ---------- KEA DHCPv6 ----------
cat > /etc/kea/kea-dhcp6.conf <<EOF
{
  "Dhcp6": {
    "interfaces-config": {
      "interfaces": ["$LAN_IF"]
    },
    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/dhcp6.leases"
    },
    "shared-networks": [
      {
        "name": "lan",
        "subnet6": [
          {
            "id": 1,
            "subnet": "$IPV6_SUBNET",
            "interface": "$LAN_IF",
            "pools": [
              { "pool": "$IPV6_POOL_START - $IPV6_POOL_END" }
            ],
            "option-data": [
              { "name": "dns-servers", "data": "$DNS6" }
            ],
            "preferred-lifetime": $LIFETIME,
            "valid-lifetime": $LIFETIME,
            "renew-timer": $RENEW6,
            "rebind-timer": $REBIND6
          }
        ]
      }
    ],
    "valid-lifetime": $LIFETIME,
    "preferred-lifetime": $LIFETIME,
    "renew-timer": $RENEW6,
    "rebind-timer": $REBIND6,
    "loggers": [
      {
        "name": "kea-dhcp6",
        "output_options": [
          { "output": "/var/log/kea/kea-dhcp6.log", "maxsize": 1048576, "maxver": 3 }
        ],
        "severity": "DEBUG",
        "debuglevel": 99
      }
    ]
  }
}
EOF

# ---------- RADVD ----------
cat > /etc/radvd.conf <<EOF
interface $LAN_IF {
    AdvSendAdvert on;
    AdvManagedFlag on;
    AdvOtherConfigFlag on;

    prefix $RADVD_PREFIX {
        AdvOnLink on;
        AdvAutonomous off;
        AdvPreferredLifetime $LIFETIME;
        AdvValidLifetime $LIFETIME;
    };
};
EOF

# ---------- NETPLAN ----------
cat > /etc/netplan/01-network-manager-all.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager

  ethernets:
    eth0:
      dhcp4: true
      dhcp6: true
      accept-ra: true

    $LAN_IF:
      dhcp4: false
      dhcp6: false
      addresses:
        - $IPV4_ADDR
        - $IPV6_ADDR
EOF

chmod 600 /etc/netplan/01-network-manager-all.yaml

echo "✅ NAT_PI configuration generated successfully (LAN_IF=$LAN_IF)"

#==============================================================

#Start Kea and Radvd Services

SERVICES=(
  kea-dhcp6-server
  kea-dhcp4-server
  radvd
)

echo "Restarting network services..."
echo "--------------------------------"

FAILED=0

sudo netplan apply

for svc in "${SERVICES[@]}"; do
  echo "Restarting $svc ..."
  systemctl restart "$svc"

  sleep 1  # small grace period

  if systemctl is-active --quiet "$svc"; then
    echo "[OK] $svc is running"
  else
    echo "[FAIL] $svc is NOT running"
    FAILED=1
  fi
done

echo "--------------------------------"

if [ "$FAILED" -eq 0 ]; then
  echo "✅ All services restarted and running successfully."
else
  echo "❌ One or more services failed to start."
fi

systemctl is-active --quiet kea-dhcp4-server && echo "✅ kea-dhcp4-server is RUNNING" || echo "❌ kea-dhcp4-server FAILED"
systemctl is-active --quiet kea-dhcp6-server && echo "✅ kea-dhcp6-server is RUNNING" || echo "❌ kea-dhcp6-server FAILED"
systemctl is-active --quiet radvd && echo "✅ radvd is RUNNING" || echo "❌ radvd FAILED"

#==============================================================
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

IFACE="eth0"

ensure_single_masquerade_rule iptables $IFACE
ensure_single_masquerade_rule ip6tables $IFACE

netfilter-persistent save
