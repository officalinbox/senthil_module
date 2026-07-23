#!/bin/bash
# ==============================================================================
# Puppet Task: RHEL Storage Setup (LVM Management)
# Supports: create_storage, extend_lv, generic
# Features: RHEL check, raw disk safety, dynamic hostname, ext4 secure fstab
# ==============================================================================

set -eo pipefail

json_result() {
    local status="$1"
    local message="$2"
    echo "{\"status\": \"${status}\", \"message\": \"${message}\"}"
}

# ========================== Only RHEL Allowed ==========================
if ! grep -qE 'Red Hat Enterprise Linux|CentOS|Rocky|AlmaLinux' /etc/redhat-release 2>/dev/null; then
    json_result "error" "This task is designed to run only on RHEL-based systems."
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    json_result "error" "This task must be run as root."
    exit 1
fi

FSTYPE="${PT_fstype:-ext4}"
HOSTNAME="$(hostname -s)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== Puppet Task Started on ${HOSTNAME} (RHEL - fstype=${FSTYPE}) ==="

# ----------------------------- Helper Functions -----------------------------
sanitize_lvm_name() {
    echo "$1" | sed 's/[^a-zA-Z0-9._-]/_/g' | sed 's/^_//;s/_$//'
}

resolve_param() {
    local value="$1"
    value="${value//\$\(hostname\)/$HOSTNAME}"
    value="${value//\$\{HOSTNAME\}/$HOSTNAME}"
    echo "$value"
}

# Resolve and sanitize names
PT_vg_name=$(resolve_param "${PT_vg_name}")
PT_lv_name=$(resolve_param "${PT_lv_name}")
PT_mount_path="${PT_mount_path}"

PT_vg_name=$(sanitize_lvm_name "$PT_vg_name")
PT_lv_name=$(sanitize_lvm_name "$PT_lv_name")

# fstab options
get_fstab_options() {
    [[ "$FSTYPE" == "ext4" ]] && echo "nosuid,nodev,rw" || echo "defaults"
}
get_fstab_dump_pass() {
    [[ "$FSTYPE" == "ext4" ]] && echo "1 2" || echo "0 0"
}

# Safety check for pvcreate
is_raw_disk() {
    local dev="$1"
    if [[ ! -b "$dev" ]]; then
        log "Error: $dev is not a valid block device."
        return 1
    fi
    if pvs "$dev" &>/dev/null; then
        log "Warning: $dev is already a Physical Volume."
        return 1
    fi
    if mount | grep -q "^$dev"; then
        log "Error: $dev is currently mounted."
        return 1
    fi
    return 0
}

# Resize filesystem
resize_fs() {
    local dev_path="$1"
    local mount_path="$2"
    local fs_type=$(lsblk -f "$dev_path" -no FSTYPE | head -n 1 2>/dev/null || echo "unknown")
    log "Resizing ${fs_type} on ${dev_path}"

    if [[ "$fs_type" == "xfs" ]]; then
        local mp=$(lsblk -f "$dev_path" -no MOUNTPOINT | head -n 1)
        if [[ -n "$mp" ]]; then
            xfs_growfs "$mp"
        elif [[ -n "$mount_path" ]]; then
            mkdir -p "$mount_path" && mount "$dev_path" "$mount_path" && xfs_growfs "$mount_path" && umount "$mount_path"
        fi
    elif [[ "$fs_type" =~ ext[234] ]]; then
        resize2fs "$dev_path"
    fi
}

# ==============================================================================
# GENERIC MODE
# ==============================================================================
if [[ "$PT_action_type" == "generic" ]]; then
    log "Mode: generic"

    if [[ -n "$PT_mount_path" && -e "$PT_mount_path" ]]; then
        log "Processing mount path: $PT_mount_path"

        if [[ -n "$PT_file_owner" || -n "$PT_file_group" ]]; then
            OWNER="${PT_file_owner:-root}"
            GROUP="${PT_file_group:-root}"
            log "Changing ownership to ${OWNER}:${GROUP}"
            chown -R "${OWNER}:${GROUP}" "$PT_mount_path" || log "Warning: chown failed"
        fi

        if [[ -n "$PT_file_mode" ]]; then
            log "Setting permissions to $PT_file_mode"
            chmod -R "$PT_file_mode" "$PT_mount_path"
        fi

        log "Current status of $PT_mount_path:"
        ls -ld "$PT_mount_path"
    elif [[ -n "$PT_mount_path" ]]; then
        log "Warning: mount_path '$PT_mount_path' does not exist."
    fi

    # PV Creation (with safety)
    if [[ -n "$PT_pv_device" ]]; then
        if is_raw_disk "$PT_pv_device"; then
            log "Creating PV on raw disk: $PT_pv_device"
            pvcreate -y "$PT_pv_device"
        fi
    fi
fi

# ==============================================================================
# CREATE STORAGE MODE
# ==============================================================================
if [[ "$PT_action_type" == "create_storage" ]]; then
    log "Mode: create_storage"

    if [[ -n "$PT_pv_device" ]] && is_raw_disk "$PT_pv_device"; then
        log "Creating PV: $PT_pv_device"
        pvcreate -y "$PT_pv_device"
    fi

    if ! vgs "$PT_vg_name" &>/dev/null && [[ -n "$PT_vg_name" && -n "$PT_pv_device" ]]; then
        log "Creating VG: $PT_vg_name"
        vgcreate "$PT_vg_name" "$PT_pv_device"
    fi

    LV_PATH="/dev/mapper/${PT_vg_name}-${PT_lv_name}"
    if ! lvs "$LV_PATH" &>/dev/null && [[ -n "$PT_lv_name" && -n "$PT_lv_size" ]]; then
        log "Creating LV: ${PT_lv_name} (${PT_lv_size})"
        lvcreate -L "$PT_lv_size" -n "$PT_lv_name" "$PT_vg_name"
        log "Formatting with ${FSTYPE}"
        mkfs -t "$FSTYPE" "$LV_PATH"
    fi

    mkdir -p "$PT_mount_path"
    FSTAB_OPTIONS=$(get_fstab_options)
    FSTAB_DUMP_PASS=$(get_fstab_dump_pass)
    FSTAB_LINE="/dev/mapper/${PT_vg_name}-${PT_lv_name} ${PT_mount_path} ${FSTYPE} ${FSTAB_OPTIONS} ${FSTAB_DUMP_PASS}"

    if ! grep -qF "${PT_vg_name}-${PT_lv_name}" /etc/fstab; then
        log "Adding fstab entry"
        echo "$FSTAB_LINE" >> /etc/fstab
    fi

    systemctl daemon-reload
    mount -a
fi

# ==============================================================================
# EXTEND LV MODE
# ==============================================================================
if [[ "$PT_action_type" == "extend_lv" ]]; then
    log "Mode: extend_lv"
    if [[ -z "$PT_lv_size" ]]; then
        json_result "error" "lv_size is required for extend_lv"
        exit 1
    fi

    LV_PATH="/dev/mapper/${PT_vg_name}-${PT_lv_name}"
    log "Extending ${LV_PATH} by/to ${PT_lv_size}"
    lvextend -L "$PT_lv_size" "$LV_PATH" || true
    resize_fs "$LV_PATH" "${PT_mount_path:-}"
fi

log "=== Puppet Task Completed Successfully on ${HOSTNAME} ==="
json_result "success" "Task completed successfully on ${HOSTNAME}"
exit 0
