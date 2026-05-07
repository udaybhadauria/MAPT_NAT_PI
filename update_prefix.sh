#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config_ui.json"

# Extract base prefix from dhcp6.subnet (remove /xx)
OLD_PREFIX=$(jq -r '.dhcp6.subnet' "$CONFIG" | sed 's|/.*||')
echo "Detected old prefix: $OLD_PREFIX"
NEW_PREFIX="$1"

if [[ -z "$OLD_PREFIX" || "$OLD_PREFIX" != *"::" ]]; then
  echo "❌ Could not detect base prefix"
  exit 1
fi

#read -p "Enter new prefix (example 2601:a40:700:8900::): " NEW_PREFIX

if [[ -z "$NEW_PREFIX" || "$NEW_PREFIX" != *"::" ]]; then
  echo "❌ Invalid new prefix"
  exit 1
fi

TMP_FILE="$(mktemp)"

jq --arg old "$OLD_PREFIX" --arg new "$NEW_PREFIX" '
  walk(
    if type == "string"
    then gsub($old; $new)
    else .
    end
  )
' "$CONFIG" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG"

echo "✅ Prefix updated successfully"
