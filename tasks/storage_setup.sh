#!/bin/bash
# ==============================================================================
# Puppet Task: RHEL 8 / RHEL 9 - Storage Setup (LVM)
# Fixed: Dynamic hostname in VG/LV names + better parameter sanitization
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
HOSTNAME="$(hostname -s)"   # Short hostname, safer for LVM names

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== Puppet Task Started on ${HOSTNAME} (fstype=${FSTYPE}) ==="

# ----------------------------- Helper: Sanitize LVM Names -----------------------------
sanitize_lvm_name() {
    echo "$1" | sed 's/[^a-zA-Z0-9._-]/_/g' | sed 's/^_//;s/_$//'
}

# Resolve dynamic hostname in parameters
resolve_param() {
    local value="$1"
    # Replace common patterns like $(hostname), ${HOSTNAME}, etc.
    value="${value//\$\(hostname\)/$HOSTNAME}"
    value="${value//\$\{HOSTNAME\}/$HOSTNAME}"
    value="${value//%HOSTNAME%/$HOSTNAME}"
    echo "$value"
}

# Apply resolution to key parameters
PT_vg_name=$(resolve_param "${PT_vg_name}")
PT_lv_name=$(resolve_param "${PT_lv_name}")
PT_pv_device="${PT_pv_device}"

PT_vg_name=$(sanitize_lvm_name "$PT_vg_name")
PT_lv_name=$(sanitize_lvm_name "$PT_lv_name")

# ----------------------------- Resize Filesystem -----------------------------
resize_fs() {
    local dev_path="$1"
    local mount_path="$2"
    local fs_type
    fs_type=$(lsblk -f "$dev_path" -no FSTYPE | head -n 1)

    log "Resizing ${fs_type} on ${dev_path}"

    if [[ "$fs_type" == "xfs" ]]; then
        local mp=$(lsblk -f "$dev_path" -no MOUNTPOINT | head -n 1)
        if [[ -n "$mp" ]]; then
            xfs_growfs "$mp"
        elif [[ -n "$mount_path" ]]; then
            mkdir -p "$mount_path" && mount "$dev_path" "$mount_path"
            xfs_growfs "$mount_path"
            umount "$mount_path"
        fi
    elif [[ "$fs_type" =~ ext[234] ]]; then
        resize2fs "$dev_path"
    fi
    log "${fs_type} resize completed"
}

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

case "$PT_action_type" in
    create_storage)
        log "Mode: create_storage | VG=${PT_vg_name} | LV=${PT_lv_name}"

        if [[ -z "$PT_pv_device" || -z "$PT_vg_name" || -z "$PT_lv_name" || -z "$PT_lv_size" || -z "$PT_mount_path" ]]; then
            json_result "error" "Missing required parameters for create_storage"
            exit 1
        fi

        if ! pvs "$PT_pv_device" &>/dev/null; then
            log "Creating PV: $PT_pv_device"
            pvcreate -y "$PT_pv_device"
        fi

        if ! vgs "$PT_vg_name" &>/dev/null; then
            log "Creating VG: $PT_vg_name"
            vgcreate "$PT_vg_name" "$PT_pv_device"
        fi

        LV_PATH="/dev/mapper/${PT_vg_name}-${PT_lv_name}"
        if ! lvs "$LV_PATH" &>/dev/null; then
            log "Creating LV: ${PT_lv_name} (${PT_lv_size})"
            lvcreate -L "$PT_lv_size" -n "$PT_lv_name" "$PT_vg_name"
            log "Formatting with ${FSTYPE}"
            mkfs -t "$FSTYPE" "$LV_PATH"
        fi

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
        log "Mode: extend_lv | VG=${PT_vg_name} | LV=${PT_lv_name}"
        if [[ -z "$PT_vg_name" || -z "$PT_lv_name" || -z "$PT_lv_size" ]]; then
            json_result "error" "Missing parameters for extend_lv"
            exit 1
        fi

        LV_PATH="/dev/mapper/${PT_vg_name}-${PT_lv_name}"
        log "Extending ${LV_PATH} to/by ${PT_lv_size}"
        lvextend -L "$PT_lv_size" "$LV_PATH" || true
        resize_fs "$LV_PATH" "${PT_mount_path:-}"
        ;;

    *)
        log "Mode: generic"
        ;;
esac

# Shared operations
[[ -n "$PT_package_name" ]] && { log "Installing $PT_package_name"; dnf install -y "$PT_package_name"; }

log "=== Puppet Task Completed Successfully on ${HOSTNAME} ==="
json_result "success" "Task completed successfully on ${HOSTNAME}"
exit 0
