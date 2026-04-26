#!/bin/bash

CONFIG="/root/NAT_PI/config_ui.json"

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

jq --arg old "$OLD_PREFIX" --arg new "$NEW_PREFIX" '
  walk(
    if type == "string"
    then gsub($old; $new)
    else .
    end
  )
' "$CONFIG" > /tmp/config_ui.json && mv /tmp/config_ui.json "$CONFIG"

echo "✅ Prefix updated successfully"
