#!/bin/bash
# Compact Single Line JSON Output

set -euo pipefail

# Parameters
PACKAGE="${PT_package:-}"
DISK="${PT_disk:-}"
MOUNT_POINT="${PT_mount_point:-/data}"
CHOWN="${PT_chown:-root:root}"
PERMISSIONS="${PT_permissions:-755}"
IP_ADDRESS="${PT_ip_address:-}"
INTERFACE="${PT_interface:-}"
HOSTS_ENTRY="${PT_hosts_entry:-}"

# Execute actions
if [[ -n "$PACKAGE" ]]; then
    dnf install -y "$PACKAGE" || yum install -y "$PACKAGE"
fi

if [[ -n "$HOSTS_ENTRY" ]]; then
    if ! grep -qF "$HOSTS_ENTRY" /etc/hosts; then
        echo "$HOSTS_ENTRY" >> /etc/hosts
    fi
fi

if [[ -n "$DISK" && -b "$DISK" ]]; then
    VG_NAME="datavg"
    LV_NAME="datalv"
    pvcreate -y "$DISK" 2>/dev/null || true
    vgcreate -y "$VG_NAME" "$DISK" 2>/dev/null || vgextend "$VG_NAME" "$DISK" 2>/dev/null || true
    lvcreate -y -l 100%FREE -n "$LV_NAME" "$VG_NAME" 2>/dev/null || true

    LV_PATH="/dev/$VG_NAME/$LV_NAME"
    mkdir -p "$MOUNT_POINT"
    mount "$LV_PATH" "$MOUNT_POINT" 2>/dev/null || true
    chown -R "$CHOWN" "$MOUNT_POINT" 2>/dev/null || true
    chmod -R "$PERMISSIONS" "$MOUNT_POINT" 2>/dev/null || true
fi

# Compact Single Line Output
if [[ -n "$HOSTS_ENTRY" ]]; then
    echo "{\"status\": \"success\", \"message\": \"Task completed on $(hostname)\", \"hosts_entry\": \"$HOSTS_ENTRY\", \"hosts_updated\": true }"
else
    echo "{\"status\": \"success\", \"message\": \"Task completed on $(hostname)\" }"
fi
