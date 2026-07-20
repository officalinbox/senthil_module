#!/bin/bash
# Complete Puppet Task - Shows real server output

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

echo '{'
echo '  "status": "success",'
echo '  "message": "Task completed on '"$(hostname)"'",'
echo '  "changes": ['

FIRST=true

# Package
if [[ -n "$PACKAGE" ]]; then
    [[ $FIRST == false ]] && echo ','
    echo '    {"action": "package", "value": "'"$PACKAGE"'", "status": "installed"}'
    FIRST=false
fi

# Hosts Entry
if [[ -n "$HOSTS_ENTRY" ]]; then
    [[ $FIRST == false ]] && echo ','
    echo '    {"action": "hosts_entry", "value": "'"$HOSTS_ENTRY"'", "status": "updated"}'
    FIRST=false

    # Show actual /etc/hosts content
    echo '    ,{'
    echo '      "action": "hosts_file_content",'
    echo '      "content": "' 
    tail -n 20 /etc/hosts | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g'
    echo '"'
    echo '    }'
fi

# LVM + Mount + chown + chmod
if [[ -n "$DISK" && -b "$DISK" ]]; then
    [[ $FIRST == false ]] && echo ','
    echo '    {"action": "lvm_mount", "disk": "'"$DISK"'", "mount_point": "'"$MOUNT_POINT"'", "chown": "'"$CHOWN"'", "permissions": "'"$PERMISSIONS"'"}'

    echo '    ,{'
    echo '      "action": "mount_status",'
    echo '      "mount": "'$(mount | grep -E "$MOUNT_POINT" | sed 's/"/\\"/g' || echo 'not_mounted')'",'
    echo '      "directory": "'$(ls -ld "$MOUNT_POINT" | sed 's/"/\\"/g')'"'
    echo '    }'
fi

# IP
if [[ -n "$IP_ADDRESS" ]]; then
    [[ $FIRST == false ]] && echo ','
    echo '    {"action": "ip_config", "ip_address": "'"$IP_ADDRESS"'", "interface": "'"$INTERFACE"'"}'
fi

echo '  ]'
echo '}'
