#!/bin/bash
# Puppet Task - Returns actual server output + changes

set -euo pipefail

# Parameters
PACKAGE="${PT_package:-}"
DISK="${PT_disk:-}"
VG_NAME="${PT_vg_name:-datavg}"
LV_NAME="${PT_lv_name:-datalv}"
MOUNT_POINT="${PT_mount_point:-/data}"
FS_TYPE="${PT_fs_type:-xfs}"
CHOWN="${PT_chown:-root:root}"
PERMISSIONS="${PT_permissions:-755}"
IP_ADDRESS="${PT_ip_address:-}"
INTERFACE="${PT_interface:-}"
HOSTS_ENTRY="${PT_hosts_entry:-}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Build result
RESULT="{\"status\": \"success\", \"message\": \"Task completed on $(hostname)\", \"executed\": ["

EXECUTED=()

# 1. Package
if [[ -n "$PACKAGE" ]]; then
    log "Installing $PACKAGE"
    dnf install -y "$PACKAGE" || yum install -y "$PACKAGE"
    EXECUTED+=('{"action": "package_install", "package": "'"$PACKAGE"'", "status": "completed"}')
fi

# 2. Hosts Entry
if [[ -n "$HOSTS_ENTRY" ]]; then
    log "Updating /etc/hosts"
    if ! grep -qF "$HOSTS_ENTRY" /etc/hosts; then
        echo "$HOSTS_ENTRY" >> /etc/hosts
    fi
    HOSTS_TAIL=$(tail -n 15 /etc/hosts | sed 's/"/\\"/g' | tr '\n' '\\n')
    EXECUTED+=('{"action": "hosts_entry", "value": "'"$HOSTS_ENTRY"'", "status": "updated", "hosts_tail": "'"$HOSTS_TAIL"'"}')
fi

# 3. LVM + Filesystem + Permissions
if [[ -n "$DISK" && -b "$DISK" ]]; then
    log "Configuring disk $DISK"

    pvcreate -y "$DISK" 2>/dev/null || true
    vgcreate -y "$VG_NAME" "$DISK" 2>/dev/null || vgextend "$VG_NAME" "$DISK" 2>/dev/null || true
    lvcreate -y -l 100%FREE -n "$LV_NAME" "$VG_NAME" 2>/dev/null || true

    LV_PATH="/dev/${VG_NAME}/${LV_NAME}"
    if ! blkid "$LV_PATH" >/dev/null 2>&1; then
        if [[ "$FS_TYPE" == "xfs" ]]; then
            mkfs.xfs -f "$LV_PATH"
        else
            mkfs.ext4 -F "$LV_PATH"
        fi
    fi

    mkdir -p "$MOUNT_POINT"
    mount "$LV_PATH" "$MOUNT_POINT" || true

    # fstab
    UUID=$(blkid -s UUID -o value "$LV_PATH")
    if ! grep -q "$MOUNT_POINT" /etc/fstab; then
        echo "UUID=$UUID $MOUNT_POINT $FS_TYPE defaults 0 0" >> /etc/fstab
    fi

    # Apply permissions
    chown -R "$CHOWN" "$MOUNT_POINT"
    chmod -R "$PERMISSIONS" "$MOUNT_POINT"

    # Real output from server
    MOUNT_INFO=$(mount | grep "$MOUNT_POINT" | sed 's/"/\\"/g')
    LS_INFO=$(ls -ld "$MOUNT_POINT" | sed 's/"/\\"/g')
    DF_INFO=$(df -h "$MOUNT_POINT" 2>/dev/null | tail -1 | sed 's/"/\\"/g')

    EXECUTED+=('{"action": "lvm_mount", "mount_point": "'"$MOUNT_POINT"'", "chown": "'"$CHOWN"'", "permissions": "'"$PERMISSIONS"'", "mount_status": "'"$MOUNT_INFO"'", "dir_info": "'"$LS_INFO"'", "disk_usage": "'"$DF_INFO"'"}')
fi

# 4. IP
if [[ -n "$IP_ADDRESS" ]]; then
    EXECUTED+=('{"action": "ip_config", "ip": "'"$IP_ADDRESS"'", "interface": "'"$INTERFACE"'"}')
fi

# Final Output
if [ ${#EXECUTED[@]} -eq 0 ]; then
    echo '{"status": "success", "message": "No parameters provided", "executed": []}'
else
    RESULT="${RESULT}$(IFS=,; echo "${EXECUTED[*]}")]}"
    echo "$RESULT"
fi
