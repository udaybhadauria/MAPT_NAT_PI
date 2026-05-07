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
detect_rpi2_mac() {
  arp -a | awk -v net="$LAN_SUBNET" -v iface="$IFACE" '
    $0 ~ net && $0 ~ iface && $1 !~ "_gateway" {
      for(i=1;i<=NF;i++){
        if($i=="at"){print tolower($(i+1)); exit}
      }
    }
  '
}

RPI2_MAC=$(detect_rpi2_mac)
if [[ -z "$RPI2_MAC" ]]; then
  echo "⚠️ Unable to detect RPI2 MAC from ARP table yet; watchdog will keep retrying"
fi

RPI2_IP=""
if [[ -n "$RPI2_MAC" ]]; then
  RPI2_IP=$(ip -6 nei | grep "$IFACE" | grep -i "$RPI2_MAC" | grep -v fe80 | awk '{print $1}')
fi

########################################
# Watchdog parameters
########################################
MAX_FAILS=2
FAIL_COUNT=0
WAITING_FOR_RETURN=0
CHECK_INTERVAL=25
RESTART_ON_DOWN_ONCE=1
DOWN_RESTART_DONE=0
DOWN_RESTART_INTERVAL=120
LAST_DOWN_RESTART_TS=0

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
  log "🔁 Restarting services"
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
  if [[ -n "$RPI2_IP" ]] && ! ping -6 -c 2 -W 2 "$RPI2_IP" >/dev/null 2>&1; then
     echo "⏭ Ping failed — BR PI is not reachable yet"
  fi

#echo "✅ Ping successful"

########################################
# Main loop
########################################
while true; do
  if [[ -z "$RPI2_MAC" ]]; then
    RPI2_MAC=$(detect_rpi2_mac)
    if [[ -n "$RPI2_MAC" ]]; then
      log "🖧 RPI2 MAC discovered: $RPI2_MAC"
    else
      log "⚠️ RPI2 MAC not in ARP table yet; continuing to monitor"
    fi
  fi

  if [[ -n "$RPI2_MAC" && -z "$RPI2_IP" ]]; then
    RPI2_IP=$(ip -6 nei | grep "$IFACE" | grep -i "$RPI2_MAC" | grep -v fe80 | awk '{print $1}')
    [[ -n "$RPI2_IP" ]] && log "🖧 RPI2 IPv6 discovered: $RPI2_IP"
  fi

  # ---------- IPv4 ARP check ----------
  if [[ -n "$RPI2_MAC" ]]; then
    ARP_OK=$(arp -a | awk -v mac="$RPI2_MAC" -v net="$LAN_SUBNET" '
      tolower($0) ~ tolower(mac) && $0 ~ net {found=1}
      END {print found+0}
    ')
  else
    ARP_OK=0
  fi

  # ---------- IPv6 neighbor check ----------
  if [[ -n "$RPI2_MAC" ]]; then
    NDP_OK=$(ip -6 neigh show dev "$IFACE" | awk -v mac="$RPI2_MAC" '
      tolower($0) ~ tolower(mac) && $NF != "FAILED" {found=1}
      END {print found+0}
    ')
  else
    NDP_OK=0
  fi

  if [[ "$ARP_OK" -eq 1 && "$NDP_OK" -eq 1 ]]; then
    if [[ "$WAITING_FOR_RETURN" -eq 1 ]]; then
      log "🟢 RPI2 back online — triggering service restart"
      restart_services

      bash /root/NAT_PI/generate_nat_routes.sh || log "❌ Route regeneration failed"

      WAITING_FOR_RETURN=0
      DOWN_RESTART_DONE=0
      LAST_DOWN_RESTART_TS=0
    else
      log "✅ RPI2 reachable (ARP + NDP OK)"
    fi

    FAIL_COUNT=0

  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log "⚠️ RPI2 missing: ARP=$ARP_OK NDP=$NDP_OK (fail $FAIL_COUNT/$MAX_FAILS)"

    if [[ "$FAIL_COUNT" -ge "$MAX_FAILS" ]]; then
      if [[ "$WAITING_FOR_RETURN" -eq 0 ]]; then
        WAITING_FOR_RETURN=1
        log "⏳ RPI2 considered down — waiting for ARP + NDP to return"

        if [[ "$RESTART_ON_DOWN_ONCE" -eq 1 && "$DOWN_RESTART_DONE" -eq 0 ]]; then
          log "🔁 RPI2 down transition detected — restarting services"
          restart_services
          DOWN_RESTART_DONE=1
          LAST_DOWN_RESTART_TS=$(date +%s)
        fi
      fi

      NOW_TS=$(date +%s)
      if [[ "$WAITING_FOR_RETURN" -eq 1 && "$NOW_TS" -ge $((LAST_DOWN_RESTART_TS + DOWN_RESTART_INTERVAL)) ]]; then
        log "🔁 RPI2 still down for ${DOWN_RESTART_INTERVAL}s — periodic service restart"
        restart_services
        LAST_DOWN_RESTART_TS=$NOW_TS
      fi
    fi
  fi

  sleep "$CHECK_INTERVAL"
done
