#!/bin/bash
# Post-build: fix boot, DTB, PARTLABEL, touchscreen, WiFi, lockscreen
set -e

WORK="$1"
IMG="$2"

if [ -z "$IMG" ]; then
    IMG=$(find "$WORK" -name "*.img" -not -name "*.img.*" | head -1)
fi

echo "Image: $IMG"

DTB_SRC="$WORK/../../userpatches/dtb/rockchip/rk3566-torder-tablet.dtb"
if [ ! -f "$DTB_SRC" ]; then
    DTB_SRC="$WORK/../../../../TorderTable-Armbian/dtb/rockchip/rk3566-torder-tablet.dtb"
fi

LOOP=$(sudo losetup -fP --show "$IMG")
sleep 1
TMPDIR=$(mktemp -d)
sudo mount "${LOOP}p1" "$TMPDIR"
echo "Mounted at $TMPDIR"

# ============================================================
# 1. DTB
# ============================================================
sudo mkdir -p "$TMPDIR/boot/dtb/rockchip"
sudo mkdir -p "$TMPDIR/boot/dtb-6.1.115-vendor-rk35xx/rockchip"
if [ -f "$DTB_SRC" ]; then
    sudo cp "$DTB_SRC" "$TMPDIR/boot/dtb/rockchip/"
    sudo cp "$DTB_SRC" "$TMPDIR/boot/dtb-6.1.115-vendor-rk35xx/rockchip/"
    echo "DTB installed"
fi

# Panthor overlay
sudo mkdir -p "$TMPDIR/boot/dtb/rockchip/overlay"
sudo mkdir -p "$TMPDIR/boot/dtb-6.1.115-vendor-rk35xx/rockchip/overlay"
PANTHOR=$(find "$TMPDIR/boot/dtb-6.1.115-vendor-rk35xx/rockchip/overlay/" -name "*panthor*" 2>/dev/null | head -1)
if [ -n "$PANTHOR" ]; then
    sudo cp "$PANTHOR" "$TMPDIR/boot/dtb/rockchip/overlay/" 2>/dev/null || true
    echo "Panthor overlay copied"
fi

# ============================================================
# 2. armbianEnv.txt
# ============================================================
sudo tee "$TMPDIR/boot/armbianEnv.txt" > /dev/null << 'EOF'
verbosity=1
bootlogo=true
console=both
extraargs=cma=256M
overlay_prefix=rk35xx
overlays=panthor-gpu
fdtfile=rockchip/rk3566-torder-tablet.dtb
rootdev=PARTLABEL=rootfs
rootfstype=ext4
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
EOF
echo "armbianEnv.txt set"

# ============================================================
# 3. PARTLABEL initramfs fix
# ============================================================
LOCAL_SCRIPT="$TMPDIR/usr/share/initramfs-tools/scripts/local"
if [ -f "$LOCAL_SCRIPT" ]; then
    sudo sed -i 's/PARTUUID=\*/PARTUUID=*|PARTLABEL=*/' "$LOCAL_SCRIPT"
    echo "initramfs PARTLABEL patched"
fi

# ============================================================
# 4. Rebuild initramfs
# ============================================================
sudo mount --bind /dev "$TMPDIR/dev" 2>/dev/null || true
sudo mount --bind /proc "$TMPDIR/proc" 2>/dev/null || true
sudo mount --bind /sys "$TMPDIR/sys" 2>/dev/null || true
sudo chroot "$TMPDIR" mkinitramfs -o /boot/initrd.img 6.1.115-vendor-rk35xx 2>&1 || echo "mkinitramfs failed"
sudo chroot "$TMPDIR" mkimage -A arm -O linux -T ramdisk -C gzip -d /boot/initrd.img /boot/uInitrd 2>&1 || echo "mkimage failed"
echo "initramfs rebuilt"

# ============================================================
# 5. Touchscreen auto-load
# ============================================================
sudo mkdir -p "$TMPDIR/etc/modules-load.d"
echo "gsl3673-800x1280" | sudo tee "$TMPDIR/etc/modules-load.d/touchscreen.conf" > /dev/null
if ! grep -q "gsl3673-800x1280" "$TMPDIR/etc/modules" 2>/dev/null; then
    echo "gsl3673-800x1280" | sudo tee -a "$TMPDIR/etc/modules" > /dev/null
fi
echo "Touchscreen auto-load configured"

# ============================================================
# 6. WiFi firmware fixes
# ============================================================
FW="$TMPDIR/lib/firmware"
if [ -d "$FW/uwe5621ds" ]; then
    sudo ln -sf wcnmodem.bin "$FW/uwe5621ds/wcnmodem_2ant.bin" 2>/dev/null || true
    sudo cp "$FW/uwe5621ds/wifi_56630001_2ant.ini" "$FW/" 2>/dev/null || true
    sudo cp "$FW/uwe5621ds/wcnmodem.bin" "$FW/" 2>/dev/null || true
    sudo cp "$FW/uwe5621ds/wcnmodem_2ant.bin" "$FW/" 2>/dev/null || true
    echo "WiFi firmware symlinks created"
fi

# ============================================================
# 7. evtest (for lockscreen-monitor)
# ============================================================
sudo chroot "$TMPDIR" apt-get install -y evtest 2>/dev/null || echo "evtest install attempted"

# ============================================================
# 8. lockscreen-monitor service
# ============================================================
sudo mkdir -p "$TMPDIR/usr/local/bin"
sudo tee "$TMPDIR/usr/local/bin/lockscreen-monitor.sh" > /dev/null << 'SCRIPTEOF'
#!/bin/bash
BACKLIGHT="/sys/class/backlight/backlight/brightness"
MAX_BRIGHT=$(cat /sys/class/backlight/backlight/max_brightness)
POWER_DEV=""
for dev in /dev/input/event*; do
    if evtest --query "$dev" EV_KEY KEY_POWER 2>/dev/null; then POWER_DEV="$dev"; break; fi
done
if [ -z "$POWER_DEV" ]; then exit 1; fi
evtest --grab "$POWER_DEV" | while read line; do
    if echo "$line" | grep -q "code 116 (KEY_POWER), value 1"; then
        SESSION_ID=$(loginctl list-sessions --no-legend 2>/dev/null | grep -E "armbian|root" | head -1 | awk '{print $1}')
        if [ -z "$SESSION_ID" ]; then continue; fi
        LOCKED=$(loginctl show-session "$SESSION_ID" -p LockedHint 2>/dev/null | cut -d= -f2)
        if [ "$LOCKED" = "yes" ]; then
            echo "$MAX_BRIGHT" > "$BACKLIGHT" 2>/dev/null
        else
            loginctl lock-session "$SESSION_ID" 2>/dev/null
            sleep 0.3
            echo 0 > "$BACKLIGHT" 2>/dev/null
        fi
    fi
done
SCRIPTEOF
sudo chmod +x "$TMPDIR/usr/local/bin/lockscreen-monitor.sh"

sudo tee "$TMPDIR/etc/systemd/system/lockscreen-monitor.service" > /dev/null << 'SVCEOF'
[Unit]
Description=Power Key Lock Screen
After=multi-user.target
[Service]
Type=simple
ExecStart=/usr/local/bin/lockscreen-monitor.sh
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
SVCEOF
sudo chroot "$TMPDIR" systemctl enable lockscreen-monitor.service 2>/dev/null || true
echo "lockscreen-monitor installed"

# ============================================================
# 9. HandlePowerKey
# ============================================================
sudo sed -i 's/^#*HandlePowerKey=.*/HandlePowerKey=ignore/' "$TMPDIR/etc/systemd/logind.conf"
echo "HandlePowerKey=ignore"

# ============================================================
# 10. GNOME power button = nothing (no shutdown dialog)
# ============================================================
# Set dconf defaults for GNOME power button
sudo mkdir -p "$TMPDIR/etc/dconf/db/local.d"
sudo tee "$TMPDIR/etc/dconf/db/local.d/01-power" > /dev/null << 'GNOMEEOF'
[org/gnome/settings-daemon/plugins/power]
power-button-action='nothing'
GNOMEEOF

# Lock the setting so user can't override
sudo mkdir -p "$TMPDIR/etc/dconf/db/local.d/locks"
sudo tee "$TMPDIR/etc/dconf/db/local.d/locks/01-power" > /dev/null << 'LOCKEOF'
[org/gnome/settings-daemon/plugins/power]
power-button-action
LOCKEOF

# Compile dconf database
sudo chroot "$TMPDIR" dconf update 2>/dev/null || true
echo "GNOME power button set to nothing"

# ============================================================
# 10. depmod
# ============================================================
sudo chroot "$TMPDIR" depmod -a 6.1.115-vendor-rk35xx 2>/dev/null || true
echo "depmod done"

# ============================================================
# 11. GDM autologin
# ============================================================
GDM_CONF="$TMPDIR/etc/gdm3/custom.conf"
if [ -f "$GDM_CONF" ]; then
    sudo sed -i 's/AutomaticLoginEnable = false/AutomaticLoginEnable = true/' "$GDM_CONF"
    echo "GDM autologin enabled"
fi

# ============================================================
# Verify
# ============================================================
echo "=== Verify ==="
grep HandlePowerKey "$TMPDIR/etc/systemd/logind.conf" | grep -v '^#'
cat "$TMPDIR/etc/modules-load.d/touchscreen.conf"
ls "$TMPDIR/usr/local/bin/lockscreen-monitor.sh"
ls "$TMPDIR/etc/systemd/system/lockscreen-monitor.service"
ls "$TMPDIR/lib/firmware/uwe5621ds/wcnmodem_2ant.bin"

# Cleanup
sudo umount "$TMPDIR/dev" "$TMPDIR/proc" "$TMPDIR/sys" 2>/dev/null || true
sudo umount "$TMPDIR"
sudo losetup -d "$LOOP"
rmdir "$TMPDIR"

# GPT partition name
sudo sfdisk --part-name "$IMG" 1 rootfs 2>/dev/null || echo "sfdisk will fix at runtime"

echo "Post-build complete!"
