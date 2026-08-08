#!/bin/bash
# Post-build: fix boot files, DTB, PARTLABEL, services
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

# DTB
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
    sudo cp "$PANTHOR" "$TMPDIR/boot/dtb/rockchip/overlay/"
    echo "Panthor overlay copied"
fi

# armbianEnv.txt
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

# Patch initramfs
LOCAL_SCRIPT="$TMPDIR/usr/share/initramfs-tools/scripts/local"
if [ -f "$LOCAL_SCRIPT" ]; then
    sudo sed -i 's/PARTUUID=\*/PARTUUID=*|PARTLABEL=*/' "$LOCAL_SCRIPT"
    echo "initramfs PARTLABEL patched"
fi

# Rebuild initramfs in chroot
sudo mount --bind /dev "$TMPDIR/dev" 2>/dev/null || true
sudo mount --bind /proc "$TMPDIR/proc" 2>/dev/null || true
sudo mount --bind /sys "$TMPDIR/sys" 2>/dev/null || true
sudo chroot "$TMPDIR" mkinitramfs -o /boot/initrd.img 6.1.115-vendor-rk35xx 2>&1 || echo "mkinitramfs failed"
sudo chroot "$TMPDIR" mkimage -A arm -O linux -T ramdisk -C gzip -d /boot/initrd.img /boot/uInitrd 2>&1 || echo "mkimage failed"
sudo umount "$TMPDIR/dev" "$TMPDIR/proc" "$TMPDIR/sys" 2>/dev/null || true
echo "initramfs rebuilt"

# lockscreen-monitor
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
Description=Power Key Lock Screen & Backlight Control
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

# GDM autologin
GDM_CONF="$TMPDIR/etc/gdm3/custom.conf"
if [ -f "$GDM_CONF" ]; then
    sudo sed -i 's/AutomaticLoginEnable = false/AutomaticLoginEnable = true/' "$GDM_CONF"
    echo "GDM autologin enabled"
fi

# HandlePowerKey
sudo sed -i 's/^#*HandlePowerKey=.*/HandlePowerKey=ignore/' "$TMPDIR/etc/systemd/logind.conf"
echo "HandlePowerKey=ignore"

# Verify
echo "=== Verify ==="
md5sum "$TMPDIR/boot/dtb/rockchip/rk3566-torder-tablet.dtb" 2>/dev/null
ls -la "$TMPDIR/boot/uInitrd-6.1.115-vendor-rk35xx"
grep PARTLABEL "$TMPDIR/usr/share/initramfs-tools/scripts/local" | head -1

sudo umount "$TMPDIR"
sudo losetup -d "$LOOP"
rmdir "$TMPDIR"

# GPT partition name
sudo sfdisk --part-name "$IMG" 1 rootfs 2>/dev/null || echo "sfdisk will fix at runtime"

echo "Post-build complete!"
