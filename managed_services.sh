#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$BASE_DIR/ui_venv"

APP_PY="$BASE_DIR/app.py"
WATCHDOG_SH="$BASE_DIR/watchdog_br_pi.sh"

APP_SERVICE="/etc/systemd/system/app-pi.service"
WATCHDOG_SERVICE="/etc/systemd/system/watchdog-br-pi.service"

PYTHON="$VENV/bin/python"
PIP="$VENV/bin/pip"

echo "🔍 Validating environment..."

# -----------------------------
# Sanity checks
# -----------------------------
if [[ ! -d "$VENV" ]]; then
  echo "❌ ERROR: Virtualenv not found: $VENV"
  exit 1
fi

if [[ ! -x "$PYTHON" ]]; then
  echo "❌ ERROR: Python not found in venv: $PYTHON"
  exit 1
fi

if [[ ! -f "$APP_PY" ]]; then
  echo "❌ ERROR: app.py not found"
  exit 1
fi

if [[ ! -f "$WATCHDOG_SH" ]]; then
  echo "❌ ERROR: watchdog_br_pi.sh not found"
  exit 1
fi

chmod +x "$WATCHDOG_SH"

# -----------------------------
# Ensure Flask is installed
# -----------------------------
echo "📦 Checking Flask dependency..."
if ! "$PYTHON" -c "import flask" 2>/dev/null; then
  echo "⚠️ Flask not found in ui_venv — installing..."
  "$PYTHON" -m pip install flask
else
  echo "✅ Flask already installed in ui_venv"
fi

# -----------------------------
# Create app.py systemd service
# -----------------------------
echo "🛠 Writing app-pi.service..."

cat > "$APP_SERVICE" <<EOF
[Unit]
Description=PI Python Application (Flask)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$BASE_DIR
ExecStart=$PYTHON $APP_PY
Restart=always
RestartSec=5

StandardOutput=journal
StandardError=journal

KillSignal=SIGTERM
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

# -----------------------------
# Create watchdog systemd service
# -----------------------------
echo "🛠 Writing watchdog-br-pi.service..."

cat > "$WATCHDOG_SERVICE" <<EOF
[Unit]
Description=BR PI Watchdog (continuous)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$WATCHDOG_SH
Restart=always
RestartSec=5

StandardOutput=journal
StandardError=journal

KillSignal=SIGTERM
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

# -----------------------------
# Reload & manage services
# -----------------------------
echo "🔄 Reloading systemd daemon..."
systemctl daemon-reload

echo "✅ Enabling services..."
systemctl enable app-pi.service watchdog-br-pi.service

echo "🚀 Restarting services..."
systemctl restart app-pi.service watchdog-br-pi.service

# -----------------------------
# Status summary
# -----------------------------
echo
echo "📊 Service status:"
systemctl --no-pager --full status app-pi.service watchdog-br-pi.service

