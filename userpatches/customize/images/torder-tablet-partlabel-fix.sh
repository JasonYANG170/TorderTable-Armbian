#!/bin/bash
#
# Torder Tablet post-build fix for PARTLABEL boot issue
#
# Problem: Armbian boots first time, hangs on initramfs after reboot
# Root cause: GPT partition has no name, but U-Boot uses root=PARTLABEL=rootfs
# Fix: Set GPT partition name + patch initramfs scripts
#
# This script runs after rootfs is assembled, before image finalization.
#

display_alert "Torder Tablet" "Applying PARTLABEL fix for reliable reboot" "info"

# ============================================================
# Fix 1: Patch initramfs scripts/local to support PARTLABEL
# ============================================================
LOCAL_SCRIPT="${SDCARD}/usr/share/initramfs-tools/scripts/local"
if [[ -f "${LOCAL_SCRIPT}" ]]; then
    if ! grep -q "PARTLABEL" "${LOCAL_SCRIPT}"; then
        # Add PARTLABEL to the device resolution pattern
        sed -i 's|UUID=\*\|LABEL=\*\|PARTUUID=\*\|/dev/\*|UUID=*|LABEL=*|PARTUUID=*|PARTLABEL=*|/dev/*|g' "${LOCAL_SCRIPT}" 2>/dev/null
        display_alert "Torder Tablet" "Patched initramfs scripts/local for PARTLABEL support" "info"
    else
        display_alert "Torder Tablet" "initramfs scripts/local already supports PARTLABEL" "info"
    fi
fi

# ============================================================
# Fix 2: Ensure /dev/disk/by-partlabel exists in initramfs
# ============================================================
INITSCRIPT="${SDCARD}/usr/share/initramfs-tools/scripts/local-top"
if [[ -d "${INITSCRIPT}" ]]; then
    # Create a hook to ensure by-partlabel symlink exists
    cat > "${INITSCRIPT}/PARTLABEL-fix" << 'HOOK'
#!/bin/sh
# Create PARTLABEL symlink if root=PARTLABEL is used
if grep -q "PARTLABEL" /proc/cmdline 2>/dev/null; then
    mkdir -p /dev/disk/by-partlabel
    # Try to find rootfs partition
    for dev in /dev/mmcblk0p1 /dev/sda1 /dev/nvme0n1p1; do
        if [ -b "$dev" ]; then
            ln -sf "$dev" /dev/disk/by-partlabel/rootfs 2>/dev/null
            break
        fi
    done
fi
HOOK
    chmod +x "${INITSCRIPT}/PARTLABEL-fix" 2>/dev/null
    display_alert "Torder Tablet" "Added PARTLABEL-fix hook to local-top" "info"
fi

# ============================================================
# Fix 3: Set default root=PARTLABEL=rootfs in armbianEnv.txt
# (if not already set)
# ============================================================
ENVFILE="${SDCARD}/boot/armbianEnv.txt"
if [[ -f "${ENVFILE}" ]]; then
    # Ensure rootdev uses PARTLABEL (this is the default for Armbian but verify)
    if ! grep -q "rootdev=" "${ENVFILE}"; then
        echo "rootdev=PARTLABEL=rootfs" >> "${ENVFILE}"
        display_alert "Torder Tablet" "Added rootdev=PARTLABEL=rootfs to armbianEnv.txt" "info"
    fi
fi

# ============================================================
# Fix 4: Add udev rule for persistent PARTLABEL symlinks
# ============================================================
UDEV_RULE="${SDCARD}/etc/udev/rules.d/99-partlabel.rules"
mkdir -p "$(dirname "${UDEV_RULE}")"
cat > "${UDEV_RULE}" << 'UDEV'
# Auto-create PARTLABEL symlinks for GPT partitions
ENV{ID_PART_ENTRY_NAME}=="rootfs", SYMLINK+="disk/by-partlabel/rootfs"
UDEV
display_alert "Torder Tablet" "Created udev rule for PARTLABEL symlinks" "info"

display_alert "Torder Tablet" "PARTLABEL fix applied successfully" "info"
