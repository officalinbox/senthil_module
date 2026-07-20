#!/bin/bash
# ==============================================================================
# Puppet Task Script: RHEL 8 / RHEL 9 System Prep & Modular LVM Management
# Action Types:
#   1. create_storage : Full sequential setup (PV -> VG -> LV -> Format -> Mount)
#   2. extend_lv      : Extends existing LV and expands filesystem
#   3. generic        : Flexible execution of individual commands based on parameters
# ==============================================================================

set -eo pipefail

json_result() {
    local status="$1"
    local message="$2"
    echo "{\"status\": \"${status}\", \"message\": \"${message}\"}"
}

if [[ $EUID -ne 0 ]]; then
   json_result "error" "This task must be run as root."
   exit 1
fi

FSTYPE="${PT_fstype:-xfs}"
echo "=== Puppet Task Execution Starting on $(hostname) ==="

# Helper function for resizing filesystems
resize_fs() {
    local dev_path="$1"
    local target_mount="$2"
    local current_fs
    current_fs=$(lsblk -f "$dev_path" -no FSTYPE | head -n 1)

    if [[ "$current_fs" == "xfs" ]]; then
        echo "--> Growing XFS filesystem..."
        local active_mount
        active_mount=$(lsblk -f "$dev_path" -no MOUNTPOINT | head -n 1)
        if [[ -z "$active_mount" && -n "$target_mount" ]]; then
            mkdir -p "$target_mount"
            mount "$dev_path" "$target_mount"
            xfs_growfs "$target_mount"
            umount "$target_mount"
        elif [[ -n "$active_mount" ]]; then
            xfs_growfs "$active_mount"
        else
            echo "--> Warning: XFS requires filesystem to be mounted to grow. Skipping xfs_growfs."
        fi
    elif [[ "$current_fs" =~ ext[234] ]]; then
        echo "--> Resizing EXT filesystem..."
        resize2fs "$dev_path"
    fi
}

# ==============================================================================
# MODE 1: create_storage (Automated Full Pipeline)
# ==============================================================================
if [[ "$PT_action_type" == "create_storage" ]]; then
    if [[ -z "$PT_pv_device" || -z "$PT_vg_name" || -z "$PT_lv_name" || -z "$PT_lv_size" || -z "$PT_mount_path" ]]; then
        json_result "error" "Missing parameters for create_storage! Required: pv_device, vg_name, lv_name, lv_size, mount_path."
        exit 1
    fi

    if ! pvs "$PT_pv_device" &>/dev/null; then
        echo "--> Creating Physical Volume: $PT_pv_device"
        pvcreate -y "$PT_pv_device"
    fi

    if ! vgs "$PT_vg_name" &>/dev/null; then
        echo "--> Creating Volume Group: $PT_vg_name"
        vgcreate "$PT_vg_name" "$PT_pv_device"
    fi

    if ! lvs "/dev/${PT_vg_name}/${PT_lv_name}" &>/dev/null; then
        echo "--> Creating Logical Volume: $PT_lv_name"
        lvcreate -L "$PT_lv_size" -n "$PT_lv_name" "$PT_vg_name"
        
        echo "--> Formatting Logical Volume as $FSTYPE"
        mkfs -t "$FSTYPE" "/dev/mapper/${PT_vg_name}-${PT_lv_name}"
    fi

    if [[ ! -d "$PT_mount_path" ]]; then
        echo "--> Creating directory: $PT_mount_path"
        mkdir -p "$PT_mount_path"
    fi

    FSTAB_LINE="/dev/mapper/${PT_vg_name}-${PT_lv_name}  ${PT_mount_path}  ${FSTYPE}  defaults  0 0"
    if ! grep -q "/dev/mapper/${PT_vg_name}-${PT_lv_name}" /etc/fstab; then
        echo "--> Adding entry to /etc/fstab"
        echo "$FSTAB_LINE" >> /etc/fstab
    fi

    echo "--> Running systemctl daemon-reload and mount -a"
    systemctl daemon-reload
    mount -a
fi

# ==============================================================================
# MODE 2: extend_lv (LVM & FS Extension)
# ==============================================================================
if [[ "$PT_action_type" == "extend_lv" ]]; then
    if [[ -z "$PT_vg_name" || -z "$PT_lv_name" || -z "$PT_lv_size" ]]; then
        json_result "error" "Missing parameters for extend_lv! Required: vg_name, lv_name, lv_size."
        exit 1
    fi

    LV_PATH="/dev/mapper/${PT_vg_name}-${PT_lv_name}"
    echo "--> Extending Logical Volume $LV_PATH by/to $PT_lv_size"
    
    if [[ "$PT_lv_size" == *"+"* ]]; then
        lvextend -L "$PT_lv_size" "$LV_PATH"
    else
        lvextend -L "$PT_lv_size" "$LV_PATH" || true
    fi

    resize_fs "$LV_PATH" "$PT_mount_path"
fi

# ==============================================================================
# MODE 3: generic (Individual Task Execution)
# ==============================================================================
if [[ "$PT_action_type" == "generic" ]]; then
    
    # 1. Individual PV / VG / LV Operations
    if [[ -n "$PT_pv_device" ]]; then
        if ! pvs "$PT_pv_device" &>/dev/null; then
            echo "--> Creating PV: $PT_pv_device"
            pvcreate -y "$PT_pv_device"
        fi
    fi

    if [[ -n "$PT_vg_name" && -n "$PT_pv_device" ]]; then
        if ! vgs "$PT_vg_name" &>/dev/null; then
            echo "--> Creating VG: $PT_vg_name on $PT_pv_device"
            vgcreate "$PT_vg_name" "$PT_pv_device"
        fi
    fi

    if [[ -n "$PT_vg_name" && -n "$PT_lv_name" && -n "$PT_lv_size" && "$PT_action_type" == "generic" ]]; then
        LV_PATH="/dev/mapper/${PT_vg_name}-${PT_lv_name}"
        if ! lvs "$LV_PATH" &>/dev/null; then
            echo "--> Creating LV: $PT_lv_name ($PT_lv_size)"
            lvcreate -L "$PT_lv_size" -n "$PT_lv_name" "$PT_vg_name"
            echo "--> Formatting LV as $FSTYPE"
            mkfs -t "$FSTYPE" "$LV_PATH"
        else
            echo "--> LV $LV_PATH exists. Attempting extend..."
            lvextend -L "$PT_lv_size" "$LV_PATH" || true
            resize_fs "$LV_PATH" "$PT_mount_path"
        fi
    fi

    # 2. Directory Creation (mkdir)
    if [[ -n "$PT_mount_path" && ! -d "$PT_mount_path" ]]; then
        echo "--> Creating Directory (mkdir): $PT_mount_path"
        mkdir -p "$PT_mount_path"
    fi

    # 3. Add /etc/fstab Entry
    if [[ "$PT_add_fstab_entry" == "true" ]]; then
        if [[ -z "$PT_vg_name" || -z "$PT_lv_name" || -z "$PT_mount_path" ]]; then
            json_result "error" "add_fstab_entry requires vg_name, lv_name, and mount_path."
            exit 1
        fi
        FSTAB_LINE="/dev/mapper/${PT_vg_name}-${PT_lv_name}  ${PT_mount_path}  ${FSTYPE}  defaults  0 0"
        if ! grep -q "/dev/mapper/${PT_vg_name}-${PT_lv_name}" /etc/fstab; then
            echo "--> Appending entry to /etc/fstab"
            echo "$FSTAB_LINE" >> /etc/fstab
        fi
    fi

    # 4. systemctl daemon-reload
    if [[ "$PT_do_daemon_reload" == "true" ]]; then
        echo "--> Running systemctl daemon-reload"
        systemctl daemon-reload
    fi

    # 5. mount -a
    if [[ "$PT_do_mount_all" == "true" ]]; then
        echo "--> Running mount -a"
        mount -a
    fi

    # 6. Unmount (umount)
    if [[ "$PT_do_umount" == "true" && -n "$PT_mount_path" ]]; then
        if mountpoint -q "$PT_mount_path"; then
            echo "--> Unmounting $PT_mount_path"
            umount "$PT_mount_path"
        else
            echo "--> $PT_mount_path is not currently mounted, skipping umount."
        fi
    fi
fi

# ==============================================================================
# Shared / Standalone Tasks (Execute across modes if parameters are supplied)
# ==============================================================================

# Package Install
if [[ -n "$PT_package_name" ]]; then
    echo "--> Installing package: $PT_package_name"
    dnf install -y "$PT_package_name"
fi

# /etc/hosts entry
if [[ -n "$PT_hosts_entry" ]]; then
    if ! grep -qF "$PT_hosts_entry" /etc/hosts; then
        echo "--> Adding host entry to /etc/hosts"
        echo "$PT_hosts_entry" >> /etc/hosts
    else
        echo "--> Host entry already exists in /etc/hosts."
    fi
fi

# Directory Ownership and Permissions
if [[ -n "$PT_mount_path" && -d "$PT_mount_path" ]]; then
    if [[ -n "$PT_file_owner" || -n "$PT_file_group" ]]; then
        OWNER="${PT_file_owner:-root}"
        GROUP="${PT_file_group:-root}"
        echo "--> Changing ownership on $PT_mount_path to ${OWNER}:${GROUP}"
        chown -R "${OWNER}:${GROUP}" "$PT_mount_path"
    fi

    if [[ -n "$PT_file_mode" ]]; then
        echo "--> Changing permissions on $PT_mount_path to $PT_file_mode"
        chmod -R "$PT_file_mode" "$PT_mount_path"
    fi
fi

json_result "success" "Puppet task completed successfully on $(hostname)."
exit 0
