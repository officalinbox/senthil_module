#!/bin/bash
# ==============================================================================
# Puppet Task Script: RHEL 8 / RHEL 9 System Prep & LVM Management
# Input: Supplied via Puppet Console parameters (exposed via PT_* env vars)
# ==============================================================================

set -eo pipefail

# Helper function to print JSON output for Puppet Console
json_result() {
    local status="$1"
    local message="$2"
    echo "{\"status\": \"${status}\", \"message\": \"${message}\"}"
}

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   json_result "error" "This task must be run as root."
   exit 1
fi

# Set default filesystem type if not passed
FSTYPE="${PT_fstype:-xfs}"

echo "=== Puppet Task Execution Starting on $(hostname) ==="

# ------------------------------------------------------------------------------
# 1. Package Installation
# ------------------------------------------------------------------------------
if [[ -n "$PT_package_name" ]]; then
    echo "--> Installing package: $PT_package_name"
    dnf install -y "$PT_package_name"
fi

# ------------------------------------------------------------------------------
# 2. Host Entry Addition (/etc/hosts)
# ------------------------------------------------------------------------------
if [[ -n "$PT_hosts_entry" ]]; then
    if ! grep -qF "$PT_hosts_entry" /etc/hosts; then
        echo "--> Adding entry to /etc/hosts"
        echo "$PT_hosts_entry" >> /etc/hosts
    else
        echo "--> Host entry already exists in /etc/hosts, skipping."
    fi
fi

# ------------------------------------------------------------------------------
# 3. LVM Creation Workflow (pvcreate -> vgcreate -> lvcreate -> mkfs -> fstab)
# ------------------------------------------------------------------------------
if [[ "$PT_action_type" == "create_storage" ]]; then
    if [[ -z "$PT_pv_device" || -z "$PT_vg_name" || -z "$PT_lv_name" || -z "$PT_lv_size" || -z "$PT_mount_path" ]]; then
        json_result "error" "Missing parameters for create_storage! Required: pv_device, vg_name, lv_name, lv_size, mount_path."
        exit 1
    fi

    # Create PV
    if ! pvs "$PT_pv_device" &>/dev/null; then
        echo "--> Creating Physical Volume: $PT_pv_device"
        pvcreate -y "$PT_pv_device"
    fi

    # Create VG
    if ! vgs "$PT_vg_name" &>/dev/null; then
        echo "--> Creating Volume Group: $PT_vg_name"
        vgcreate "$PT_vg_name" "$PT_pv_device"
    fi

    # Create LV
    if ! lvs "/dev/${PT_vg_name}/${PT_lv_name}" &>/dev/null; then
        echo "--> Creating Logical Volume: $PT_lv_name"
        lvcreate -L "$PT_lv_size" -n "$PT_lv_name" "$PT_vg_name"
        
        echo "--> Formatting Logical Volume as $FSTYPE"
        mkfs -t "$FSTYPE" "/dev/mapper/${PT_vg_name}-${PT_lv_name}"
    fi

    # Create Mount Directory
    if [[ ! -d "$PT_mount_path" ]]; then
        echo "--> Creating mount directory: $PT_mount_path"
        mkdir -p "$PT_mount_path"
    fi

    # Update /etc/fstab
    FSTAB_LINE="/dev/mapper/${PT_vg_name}-${PT_lv_name}  ${PT_mount_path}  ${FSTYPE}  defaults  0 0"
    if ! grep -q "/dev/mapper/${PT_vg_name}-${PT_lv_name}" /etc/fstab; then
        echo "--> Adding entry to /etc/fstab"
        echo "$FSTAB_LINE" >> /etc/fstab
    fi

    # Reload systemd and mount
    echo "--> Running systemctl daemon-reload and mount -a"
    systemctl daemon-reload
    mount -a
fi

# ------------------------------------------------------------------------------
# 4. LVM Resize Workflow (increase LV size -> resize filesystem)
# ------------------------------------------------------------------------------
if [[ "$PT_action_type" == "extend_lv" ]]; then
    if [[ -z "$PT_vg_name" || -z "$PT_lv_name" || -z "$PT_lv_size" ]]; then
        json_result "error" "Missing parameters for extend_lv! Required: vg_name, lv_name, lv_size."
        exit 1
    fi

    LV_PATH="/dev/mapper/${PT_vg_name}-${PT_lv_name}"

    echo "--> Extending Logical Volume $LV_PATH by/to $PT_lv_size"
    
    # Check if size input contains '+' (e.g., +2G vs 10G)
    if [[ "$PT_lv_size" == *"+"* ]]; then
        lvextend -L "$PT_lv_size" "$LV_PATH"
    else
        lvextend -L "$PT_lv_size" "$LV_PATH" || true
    fi

    # Dynamically resize based on filesystem type
    CURRENT_FS=$(lsblk -f "$LV_PATH" -no FSTYPE | head -n 1)
    if [[ "$CURRENT_FS" == "xfs" ]]; then
        echo "--> Growing XFS filesystem..."
        # If filesystem is unmounted, mount temporarily to run xfs_growfs
        MOUNT_PT=$(lsblk -f "$LV_PATH" -no MOUNTPOINT | head -n 1)
        if [[ -z "$MOUNT_PT" && -n "$PT_mount_path" ]]; then
            mount "$LV_PATH" "$PT_mount_path"
            xfs_growfs "$PT_mount_path"
            umount "$PT_mount_path"
        else
            xfs_growfs "$MOUNT_PT"
        fi
    elif [[ "$CURRENT_FS" =~ ext[234] ]]; then
        echo "--> Resizing EXT filesystem..."
        resize2fs "$LV_PATH"
    fi
fi

# ------------------------------------------------------------------------------
# 5. Directory/File Ownership and Permissions
# ------------------------------------------------------------------------------
if [[ -n "$PT_mount_path" && -d "$PT_mount_path" ]]; then
    if [[ -n "$PT_file_owner" || -n "$PT_file_group" ]]; then
        OWNER="${PT_file_owner:-root}"
        GROUP="${PT_file_group:-root}"
        echo "--> Setting ownership on $PT_mount_path to ${OWNER}:${GROUP}"
        chown -R "${OWNER}:${GROUP}" "$PT_mount_path"
    fi

    if [[ -n "$PT_file_mode" ]]; then
        echo "--> Setting permissions on $PT_mount_path to $PT_file_mode"
        chmod -R "$PT_file_mode" "$PT_mount_path"
    fi
fi

json_result "success" "Puppet task completed successfully on $(hostname)."
exit 0
