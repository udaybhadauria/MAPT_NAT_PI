#!/usr/bin/env bash

########################################
# Auto-detect LAN interface
########################################
IFACE=$(ifconfig | awk -F: '/^(enx|eth1)/ {print $1; exit}')

if [[ -z "$IFACE" ]]; then
  echo "❌ No LAN interface (enx* or eth1) found"
  exit 1
fi

########################################
# Fetch LAN IPv4 subnet from interface
########################################
LAN_IP=$(ip -4 addr show dev "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)

if [[ -z "$LAN_IP" ]]; then
  echo "❌ No IPv4 address on $IFACE"
  exit 1
fi

LAN_SUBNET=$(echo "$LAN_IP" | awk -F. '{print $1"."$2"."$3"."}')

########################################
# Fetch RPI2 MAC dynamically from ARP
########################################
RPI2_MAC=$(arp -a | awk -v net="$LAN_SUBNET" -v iface="$IFACE" '
  $0 ~ net && $0 ~ iface && $1 !~ "_gateway" {
    for(i=1;i<=NF;i++){
      if($i=="at"){print $(i+1); exit}
    }
  }
')

if [[ -z "$RPI2_MAC" ]]; then
  echo "❌ Unable to detect RPI2 MAC from ARP table"
  exit 1
fi

RPI2_MAC=$(echo "$RPI2_MAC" | tr '[:upper:]' '[:lower:]')
RPI2_IP=$(ip -6 nei | grep "$IFACE" | grep -i "$RPI2_MAC" | grep -v fe80 | awk '{print $1}')

########################################
# Watchdog parameters
########################################
MAX_FAILS=2
FAIL_COUNT=0
WAITING_FOR_RETURN=0
CHECK_INTERVAL=25

SERVICES=(
  radvd
  kea-dhcp6-server
  kea-dhcp4-server
  NetworkManager
)

log() {
  echo "$(date '+%F %T') $*"
}

restart_services() {
  log "🔁 Restarting services (RPI2 confirmed back)"
  for svc in "${SERVICES[@]}"; do
    systemctl restart "$svc" 2>/dev/null || true
  done
}

log "🧠 Watchdog started"
log "🔌 LAN IFACE  : $IFACE"
log "🌐 LAN SUBNET: $LAN_SUBNET"
log "🖧 BR_PI MAC  : $RPI2_MAC"
log "🖧 BR_PI IP  : $RPI2_IP"

echo "📡 Pinging $RPI2_IP"
  if ! ping -6 -c 2 -W 2 "$RPI2_IP" >/dev/null 2>&1; then
     echo "⏭ Ping failed — BR PI is not reachable yet"
     continue
  fi

#echo "✅ Ping successful"

########################################
# Main loop
########################################
while true; do
  # ---------- IPv4 ARP check ----------
  ARP_OK=$(arp -a | awk -v mac="$RPI2_MAC" -v net="$LAN_SUBNET" '
    tolower($0) ~ tolower(mac) && $0 ~ net {found=1}
    END {print found+0}
  ')

  # ---------- IPv6 neighbor check ----------
  NDP_OK=$(ip -6 neigh show dev "$IFACE" | awk -v mac="$RPI2_MAC" '
    tolower($0) ~ tolower(mac) && $NF != "FAILED" {found=1}
    END {print found+0}
  ')

  if [[ "$ARP_OK" -eq 1 && "$NDP_OK" -eq 1 ]]; then
    if [[ "$WAITING_FOR_RETURN" -eq 1 ]]; then
      log "🟢 RPI2 back online — triggering service restart"
      restart_services

      bash /root/NAT_PI/generate_nat_routes.sh || log "❌ Route regeneration failed"

      WAITING_FOR_RETURN=0
    else
      log "✅ RPI2 reachable (ARP + NDP OK)"
    fi

    FAIL_COUNT=0

  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log "⚠️ RPI2 missing: ARP=$ARP_OK NDP=$NDP_OK (fail $FAIL_COUNT/$MAX_FAILS)"

    if [[ "$FAIL_COUNT" -ge "$MAX_FAILS" ]]; then
      WAITING_FOR_RETURN=1
      log "⏳ RPI2 considered down — waiting for ARP + NDP to return"
    fi
  fi

  sleep "$CHECK_INTERVAL"
done
