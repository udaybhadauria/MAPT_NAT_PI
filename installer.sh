#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATE_CFG_SH="$SCRIPT_DIR/generate_config.sh"
MANAGED_SERVICES_SH="$SCRIPT_DIR/managed_services.sh"
SCHEDULER_CRON_SH="$SCRIPT_DIR/scheduler_cron.sh"
 
PKGS=(
  curl tcpdump mosquitto mosquitto-clients jq yq iproute2 net-tools
  radvd kea-dhcp6-server kea-dhcp4-server apparmor-utils
  iptables-persistent dibbler-client openssh-server python3-venv
)
 
BASE_SERVICES=(
  ssh mosquitto
)

FINAL_SERVICES=(
  kea-dhcp6-server kea-dhcp4-server radvd dibbler-client ssh mosquitto
  app-pi watchdog-br-pi
)
 
VENV_DIR="$SCRIPT_DIR/ui_venv"
 
echo "[*] Updating apt..."
sudo apt update
 
echo "[*] Installing packages..."
sudo apt install -y "${PKGS[@]}"
 
echo "[*] Verifying packages..."
MISSING_PKGS=0
for p in "${PKGS[@]}"; do
  if ! dpkg -s "$p" >/dev/null 2>&1; then
    echo "[ERROR] Package missing: $p"
    MISSING_PKGS=1
  fi
done
[[ "$MISSING_PKGS" -eq 0 ]] || { echo "[ERROR] Package verification failed"; exit 1; }
echo "[OK] All packages installed."
 
echo "[*] Reloading systemd..."
sudo systemctl daemon-reload
 
echo "[*] Enabling + starting base services..."
for s in "${BASE_SERVICES[@]}"; do
  sudo systemctl enable "$s"
  sudo systemctl start "$s"
done
 
echo "[*] Verifying base services are active..."
for s in "${BASE_SERVICES[@]}"; do
  if ! systemctl is-active --quiet "$s"; then
    echo "[ERROR] Base service not running: $s"
    exit 1
  fi
done
echo "[OK] Base services running."
 
echo "[*] Configuring Mosquitto listener..."
MOSQ_CONF="/etc/mosquitto/conf.d/listener.conf"
sudo mkdir -p /etc/mosquitto/conf.d
 
sudo tee "$MOSQ_CONF" >/dev/null <<EOF
listener 1883 ::
allow_anonymous true
EOF
 
echo "[*] Restarting Mosquitto..."
sudo systemctl restart mosquitto
 
echo "[*] Verifying Mosquitto status + port..."
systemctl is-active --quiet mosquitto || { echo "[ERROR] Mosquitto not running"; exit 1; }
ss -lntp | grep -q ":1883" || { echo "[ERROR] Mosquitto not listening on 1883"; exit 1; }
echo "[OK] Mosquitto configured and listening."
 
echo "[*] Enabling IPv4 + IPv6 forwarding (runtime)..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null
echo 1 | sudo tee /proc/sys/net/ipv6/conf/all/forwarding >/dev/null
 
echo "[*] Enabling IPv6 forwarding permanently..."
if ! grep -q "^net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
  echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf >/dev/null
fi
sudo sysctl -p >/dev/null
 
echo "[*] Creating Python venv..."
if [[ -d "$VENV_DIR" ]]; then
  echo "[*] Removing existing venv at $VENV_DIR"
  rm -rf "$VENV_DIR"
fi
python3 -m venv "$VENV_DIR"
 
echo "[*] Activating venv + installing Python deps..."
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip
python -m pip install flask paho-mqtt
 
echo "[*] Verifying Python packages..."
python - <<'EOF'
import sys
try:
    import flask, paho.mqtt.client
except Exception as e:
    print("[ERROR] Python deps missing:", e)
    sys.exit(1)
print("[OK] Flask + paho-mqtt installed.")
EOF
deactivate
 
echo "[*] Setting AppArmor to complain mode..."
sudo aa-complain /usr/sbin/kea-dhcp6 || true
sudo aa-complain /usr/sbin/kea-dhcp4 || true
 
echo "[*] Verifying installer helper scripts..."
for f in "$GENERATE_CFG_SH" "$MANAGED_SERVICES_SH" "$SCHEDULER_CRON_SH"; do
  [[ -f "$f" ]] || { echo "[ERROR] Missing required script: $f"; exit 1; }
done

chmod +x "$GENERATE_CFG_SH" "$MANAGED_SERVICES_SH" "$SCHEDULER_CRON_SH"

echo "[*] Generating NAT/KEA/radvd configuration..."
sudo bash "$GENERATE_CFG_SH"

echo "[*] Fixing Kea lease file permissions..."
for lease_file in /var/lib/kea/kea-leases*.csv; do
  [[ -e "$lease_file" ]] || continue
  sudo chmod 640 "$lease_file"
  sudo chown _kea:_kea "$lease_file"
done

echo "[*] Fixing Kea config permissions..."
sudo chmod 644 /etc/kea/kea-dhcp4.conf
sudo chown root:root /etc/kea/kea-dhcp4.conf
sudo chmod 644 /etc/kea/kea-dhcp6.conf
sudo chown root:root /etc/kea/kea-dhcp6.conf

echo "[*] Validating Kea configs..."
sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
sudo kea-dhcp6 -t /etc/kea/kea-dhcp6.conf

echo "[*] Creating/starting managed systemd services..."
sudo bash "$MANAGED_SERVICES_SH"

echo "[*] Installing cron jobs..."
sudo bash "$SCHEDULER_CRON_SH"

echo "[*] Verifying final service state..."
for s in "${FINAL_SERVICES[@]}"; do
  if ! systemctl is-active --quiet "$s"; then
    echo "[ERROR] Service not running after install: $s"
    exit 1
  fi
done
 
echo
echo "======================================"
echo " ✅ ALL PACKAGES INSTALLED"
echo " ✅ PYTHON ENV READY"
echo " ✅ CONFIG GENERATED"
echo " ✅ MANAGED SERVICES APPLIED"
echo " ✅ CRON JOBS APPLIED"
echo " ✅ ALL SERVICES RUNNING"
echo " ✅ KEA CONFIGS VALID"
echo " ✅ PERMISSIONS SET"
echo "======================================"
