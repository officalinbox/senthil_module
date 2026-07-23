#!/bin/bash
# ==============================================================================
# Puppet Task: RHEL 8 / RHEL 9 - Storage Setup (LVM)
# Default FS: ext4 | Real-time logging for Puppet Console
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

FSTYPE="${PT_fstype:-ext4}"
HOSTNAME="$(hostname)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== Puppet Task Started on ${HOSTNAME} (fstype=${FSTYPE}) ==="

# ----------------------------- Resize Filesystem -----------------------------
resize_fs() {
    local dev_path="$1"
    local mount_path="$2"
    local fs_type
    fs_type=$(lsblk -f "$dev_path" -no FSTYPE | head -n 1)

    log "Resizing filesystem on ${dev_path} (detected: ${fs_type})"

    if [[ "$fs_type" == "xfs" ]]; then
        local mountpoint
        mountpoint=$(lsblk -f "$dev_path" -no MOUNTPOINT | head -n 1)
        if [[ -n "$mountpoint" ]]; then
            xfs_growfs "$mountpoint"
        elif [[ -n "$mount_path" ]]; then
            mkdir -p "$mount_path"
            mount "$dev_path" "$mount_path"
            xfs_growfs "$mount_path"
            umount "$mount_path"
        else
            log "Warning: XFS needs to be mounted to grow. Skipping."
            return 0
        fi
        log "XFS filesystem successfully grown"
    elif [[ "$fs_type" =~ ext[234] ]]; then
        resize2fs "$dev_path"
        log "EXT filesystem successfully resized"
    else
        log "Warning: Unsupported filesystem: ${fs_type}"
    fi
}

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

case "$PT_action_type" in
    create_storage)
        log "Mode: create_storage"
        if [[ -z "$PT_pv_device" || -z "$PT_vg_name" || -z "$PT_lv_name" || -z "$PT_lv_size" || -z "$PT_mount_path" ]]; then
            json_result "error" "Missing parameters for create_storage"
            exit 1
        fi

        # PV
        if ! pvs "$PT_pv_device" &>/dev/null; then
            log "Creating PV: $PT_pv_device"
            pvcreate -y "$PT_pv_device"
        fi

        # VG
        if ! vgs "$PT_vg_name" &>/dev/null; then
            log "Creating VG: $PT_vg_name"
            vgcreate "$PT_vg_name" "$PT_pv_device"
        fi

        # LV + Format
        LV_PATH="/dev/mapper/${PT_vg_name}-${PT_lv_name}"
        if ! lvs "$LV_PATH" &>/dev/null; then
            log "Creating LV: ${PT_lv_name} size=${PT_lv_size}"
            lvcreate -L "$PT_lv_size" -n "$PT_lv_name" "$PT_vg_name"
            log "Formatting with ${FSTYPE}"
            mkfs -t "$FSTYPE" "$LV_PATH"
        fi

        # Mount point & fstab
        mkdir -p "$PT_mount_path"
        FSTAB_LINE="/dev/mapper/${PT_vg_name}-${PT_lv_name} ${PT_mount_path} ${FSTYPE} defaults 0 0"
        if ! grep -qF "${PT_vg_name}-${PT_lv_name}" /etc/fstab; then
            log "Adding fstab entry"
            echo "$FSTAB_LINE" >> /etc/fstab
        fi

        systemctl daemon-reload
        mount -a
        ;;

    extend_lv)
        log "Mode: extend_lv"
        if [[ -z "$PT_vg_name" || -z "$PT_lv_name" || -z "$PT_lv_size" ]]; then
            json_result "error" "Missing parameters for extend_lv"
            exit 1
        fi

        LV_PATH="/dev/mapper/${PT_vg_name}-${PT_lv_name}"
        log "Extending LV: ${LV_PATH} → ${PT_lv_size}"
        lvextend -L "$PT_lv_size" "$LV_PATH" || true
        resize_fs "$LV_PATH" "${PT_mount_path:-}"
        ;;

    generic|*)
        log "Mode: generic"
        # Add your generic operations here if needed...
        log "Generic mode executed (extend this section as required)"
        ;;
esac

# Shared operations (works in all modes)
[[ -n "$PT_package_name" ]] && { log "Installing $PT_package_name"; dnf install -y "$PT_package_name"; }
[[ -n "$PT_mount_path" && -e "$PT_mount_path" ]] && {
    [[ -n "$PT_file_owner" || -n "$PT_file_group" ]] && chown -R "${PT_file_owner:-root}:${PT_file_group:-root}" "$PT_mount_path"
    [[ -n "$PT_file_mode" ]] && chmod -R "$PT_file_mode" "$PT_mount_path"
}

log "=== Puppet Task Completed Successfully on ${HOSTNAME} ==="
json_result "success" "Task completed successfully on ${HOSTNAME}"
exit 0
