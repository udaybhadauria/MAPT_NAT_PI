#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"

CRON_TMP="/tmp/current_cron.$$"
touch "$CRON_TMP"

# Load existing crontab if it exists
crontab -l 2>/dev/null > "$CRON_TMP" || true

# Function to add cron line if missing
add_cron_job() {
    local job="$1"
    grep -Fxq "$job" "$CRON_TMP" || echo "$job" >> "$CRON_TMP"
}

# Required cron jobs
add_cron_job "@reboot (sleep 110; /bin/bash $SCRIPT_DIR/generate_config.sh) >> $SCRIPT_DIR/zboot_logs.log 2>&1"
add_cron_job "* * * * * /bin/bash $SCRIPT_DIR/clean_ip6_neigh.sh"
add_cron_job "*/15 * * * * /bin/bash $SCRIPT_DIR/service_health_check.sh >> $SCRIPT_DIR/zboot_logs.log 2>&1"

# Install updated crontab
crontab "$CRON_TMP"

# Cleanup
rm -f "$CRON_TMP"

echo "✅ Crontab verified and updated successfully."
