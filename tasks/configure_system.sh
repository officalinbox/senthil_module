#!/bin/bash
# Puppet Task - Minimal Clean Output

set -euo pipefail

# Get parameters
PACKAGE="${PT_package:-}"
DISK="${PT_disk:-}"
VG_NAME="${PT_vg_name:-}"
LV_NAME="${PT_lv_name:-}"
MOUNT_POINT="${PT_mount_point:-}"
IP_ADDRESS="${PT_ip_address:-}"
INTERFACE="${PT_interface:-}"
HOSTS_ENTRY="${PT_hosts_entry:-}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Start JSON
JSON='{"status": "success", "message": "Task completed on '"$(hostname)"'"'

# === Only add fields that were used ===

if [[ -n "$PACKAGE" ]]; then
    log "Installing $PACKAGE"
    dnf install -y "$PACKAGE" || yum install -y "$PACKAGE"
    JSON="${JSON}, \"package_installed\": true"
fi

if [[ -n "$HOSTS_ENTRY" ]]; then
    log "Adding hosts entry: $HOSTS_ENTRY"
    if ! grep -qF "$HOSTS_ENTRY" /etc/hosts; then
        echo "$HOSTS_ENTRY" >> /etc/hosts
        JSON="${JSON}, \"hosts_entry\": \"$HOSTS_ENTRY\", \"hosts_updated\": true"
        log "✓ Hosts entry added"
    else
        JSON="${JSON}, \"hosts_entry\": \"$HOSTS_ENTRY\", \"hosts_updated\": \"already exists\""
    fi
fi

if [[ -n "$DISK" ]]; then
    log "Processing disk $DISK for LVM"
    JSON="${JSON}, \"disk_used\": \"$DISK\", \"vg\": \"$VG_NAME\", \"lv\": \"$LV_NAME\", \"mount_point\": \"$MOUNT_POINT\""
fi

if [[ -n "$IP_ADDRESS" ]]; then
    log "Configuring IP $IP_ADDRESS"
    JSON="${JSON}, \"ip_address\": \"$IP_ADDRESS\", \"interface\": \"$INTERFACE\""
fi

# Close JSON
JSON="${JSON} }"

echo "$JSON"
