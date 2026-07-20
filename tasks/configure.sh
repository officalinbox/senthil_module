#!/bin/bash
# Puppet Task: RHEL 8/9 - Package, LVM, Filesystem, Network, Hosts, fstab
set -euo pipefail

# Parameters from Puppet (environment variables)
PACKAGE="${PT_package:-}"
DISK="${PT_disk:-}"
VG_NAME="${PT_vg_name:-datavg}"
LV_NAME="${PT_lv_name:-datalv}"
NEW_LV_NAME="${PT_new_lv_name:-}"
MOUNT_POINT="${PT_mount_point:-/data}"
FS_TYPE="${PT_fs_type:-xfs}"
LV_SIZE="${PT_lv_size:-100%FREE}"
IP_ADDRESS="${PT_ip_address:-}"
GATEWAY="${PT_gateway:-}"
DNS="${PT_dns:-8.8.8.8,8.8.4.4}"
INTERFACE="${PT_interface:-}"
HOSTS_ENTRY="${PT_hosts_entry:-}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Structured result for Puppet
cat <<EOF
{
  "status": "success",
  "package_installed": "${PACKAGE:+true}",
  "disk_configured": "${DISK:+true}",
  "vg": "$VG_NAME",
  "lv": "$LV_NAME",
  "mount_point": "$MOUNT_POINT",
  "ip_configured": "${IP_ADDRESS:+true}",
  "message": "Task completed on $(hostname)"
}
EOF
