#!/bin/bash

# ------------------- Detect interfaces -------------------
IFACE=$(ifconfig | awk -F: '/^(enx|eth1)/ {print $1; exit}')
#echo "${IFACE[*]}"
#IFACE=$(ip link show | awk -F': ' '/^[0-9]+: enx/ {print $2}')

ADDR=$(ip -6 addr show dev "$IFACE" \
  | awk '/inet6/ && /scope global/ {print $2; exit}')

PREFIX=$(echo "$ADDR" | cut -d/ -f1 | cut -d: -f1-4 | sed 's/$/:/')

BR_PI=$(ip -6 neigh show dev "$IFACE" \
  | awk -v pfx="$PREFIX" '
    $1 ~ "^" pfx && $NF != "FAILED" {
        print $1;
        exit
    }')

if [[ -z "$BR_PI" ]]; then
    echo "ERROR: No reachable IPv6 neighbor found in $PREFIX"
    exit 1
fi

echo "📡 Pinging BR_PI ($BR_PI)..."

if ping -6 -c 2 -W 2 "$BR_PI" >/dev/null 2>&1; then
    #echo "✅ BR is reachable"
    BR_REACHABLE="✅Yes"
else
    #echo "❌ BR is NOT reachable"
    BR_REACHABLE="❌No"
fi

arp -a | awk '/enx0050b61d76b4/ {gsub(/[()]/,"",$2); print "BR_IPv4="$2,"BR_MAC="$4}'

echo ""
echo "Interface : $IFACE"
echo "Prefix    : $PREFIX"
echo "BR IPv6 : $BR_PI"
echo "BR Reachable over IPv6: $BR_REACHABLE"
echo "ssh -p xx pi@$BR_PI"
