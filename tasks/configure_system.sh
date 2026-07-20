#!/bin/bash
# Simple & Clean Output Version

set -euo pipefail

PACKAGE="${PT_package:-}"
DISK="${PT_disk:-}"
MOUNT_POINT="${PT_mount_point:-/data}"
CHOWN="${PT_chown:-root:root}"
PERMISSIONS="${PT_permissions:-755}"
IP_ADDRESS="${PT_ip_address:-}"
INTERFACE="${PT_interface:-}"
HOSTS_ENTRY="${PT_hosts_entry:-}"

echo '{'
echo '  "status": "success",'
echo '  "message": "Task completed on '"$(hostname)"'",'
echo '  "changes": ['

FIRST=true

# Hosts Entry
if [[ -n "$HOSTS_ENTRY" ]]; then
    [[ $FIRST == false ]] && echo ','
    echo '    {'
    echo '      "action": "hosts_entry",'
    echo '      "value": "'"$HOSTS_ENTRY"'",'
    echo '      "status": "updated"'
    echo '    }'
    FIRST=false

    # Show actual hosts content
    echo '    ,{'
    echo '      "action": "hosts_file_content",'
    echo '      "content": "' 
    tail -n 15 /etc/hosts | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g'
    echo '"'
    echo '    }'
fi

# LVM + Permissions
if [[ -n "$DISK" ]]; then
    [[ $FIRST == false ]] && echo ','
    echo '    {'
    echo '      "action": "lvm_mount",'
    echo '      "mount_point": "'"$MOUNT_POINT"'",'
    echo '      "chown": "'"$CHOWN"'",'
    echo '      "permissions": "'"$PERMISSIONS"'",'
    echo '      "status": "completed"'
    echo '    }'
fi

# Package
if [[ -n "$PACKAGE" ]]; then
    [[ $FIRST == false ]] && echo ','
    echo '    {"action": "package", "value": "'"$PACKAGE"'", "status": "installed"}'
fi

# IP
if [[ -n "$IP_ADDRESS" ]]; then
    [[ $FIRST == false ]] && echo ','
    echo '    {"action": "ip_config", "value": "'"$IP_ADDRESS"'", "status": "configured"}'
fi

echo '  ]'
echo '}'
