#!/bin/bash
# Puppet Task: Clean output - Only show used parameters

set -euo pipefail

# Parameters from Puppet Console
PACKAGE="${PT_package:-}"
DISK="${PT_disk:-}"
VG_NAME="${PT_vg_name:-}"
LV_NAME="${PT_lv_name:-}"
MOUNT_POINT="${PT_mount_point:-}"
FS_TYPE="${PT_fs_type:-}"
IP_ADDRESS="${PT_ip_address:-}"
INTERFACE="${PT_interface:-}"
HOSTS_ENTRY="${PT_hosts_entry:-}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Build dynamic JSON output
JSON_OUTPUT='{"status": "success", "message": "Task completed on '"$(hostname)"'", '

# Package
if [[ -n "$PACKAGE" ]]; then
    log "Installing package: $PACKAGE"
    dnf install -y "$PACKAGE" || yum install -y "$PACKAGE"
    JSON_OUTPUT="${JSON_OUTPUT}\"package_installed\": true, "
fi

# Hosts Entry
if [[ -n "$HOSTS_ENTRY" ]]; then
    log "Adding to /etc/hosts: $HOSTS_ENTRY"
    if ! grep -qF "$HOSTS_ENTRY" /etc/hosts; then
        echo "$HOSTS_ENTRY" >> /etc/hosts
        JSON_OUTPUT="${JSON_OUTPUT}\"hosts_entry\": \"$HOSTS_ENTRY\", \"hosts_updated\": true, "
        log "Hosts entry added successfully"
    else
        JSON_OUTPUT="${JSON_OUTPUT}\"hosts_entry\": \"$HOSTS_ENTRY\", \"hosts_updated\": \"already exists\", "
    fi
fi

# LVM / Disk
if [[ -n "$DISK" ]]; then
    log "Processing disk: $DISK"
    JSON_OUTPUT="${JSON_OUTPUT}\"disk_used\": \"$DISK\", \"vg\": \"$VG_NAME\", \"lv\": \"$LV_NAME\", \"mount_point\": \"$MOUNT_POINT\", "
fi

# IP Configuration
if [[ -n "$IP_ADDRESS" && -n "$INTERFACE" ]]; then
    log "Configuring IP on $INTERFACE"
    JSON_OUTPUT="${JSON_OUTPUT}\"ip_address\": \"$IP_ADDRESS\", \"interface\": \"$INTERFACE\", "
fi

# Finalize JSON
JSON_OUTPUT="${JSON_OUTPUT%??}"  # Remove last comma and space
JSON_OUTPUT="${JSON_OUTPUT} }"

echo "$JSON_OUTPUT"
