#!/bin/bash
set -e

# -------------------------------------------------
# Fixed parameters (as per your topology)
# -------------------------------------------------
IFACE=$(ifconfig | awk -F: '/^(enx|eth1)/ {print $1; exit}')
BR_MAC="2c:cf:67:2e:b0:4c"

# -------------------------------------------------
# Fetch ULA IPv6 of upstream BR
# -------------------------------------------------
BR_IP=$(ip -6 neigh show dev "$IFACE" \
  | awk -v mac="$BR_MAC" '
      $1 ~ /^fd/ &&
      tolower($0) ~ mac &&
      tolower($0) ~ /router/ {
        print $1; exit
      }
    ')

# -------------------------------------------------
# Validate
# -------------------------------------------------
if [[ -z "$BR_IP" ]]; then
  echo "❌ Upstream BR ULA not found on $IFACE" >&2
  exit 1
fi

# -------------------------------------------------
# Reachability check
# -------------------------------------------------
if ! ping6 -c 3 -W 2 "$BR_IP" >/dev/null 2>&1; then
  echo "❌ Upstream BR $BR_IP not reachable" >&2
  exit 1
fi

# -------------------------------------------------
# Output (machine-usable)
# -------------------------------------------------
echo "$BR_IP"
