#!/bin/bash
# Post-build: fix boot, DTB, PARTLABEL, touchscreen, WiFi, lockscreen
set -e

WORK="$1"
IMG="$2"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
UWE_ASSETS="$SCRIPT_DIR/../assets/uwe5621ds"

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
for file in hciattach_opi_arm64 wcnmodem.bin wcnmodem_2ant.bin \
    wifi_56630001_2ant.ini wifi_56630001_3ant.ini bt_configure_pskey.ini \
    bt_configure_rf.ini bt_configure_rf_marlin3e_2.ini bt_configure_rf_marlin3e_3.ini \
    torder-tablet-bluetooth torder-tablet-bluetooth.service; do
    test -f "$UWE_ASSETS/$file"
done

FW="$TMPDIR/lib/firmware"
sudo install -d "$FW/uwe5621ds" "$TMPDIR/usr/bin" "$TMPDIR/usr/lib/systemd/system"
sudo install -m 644 "$UWE_ASSETS/wcnmodem.bin" "$FW/uwe5621ds/wcnmodem.bin"
sudo install -m 644 "$UWE_ASSETS/wcnmodem_2ant.bin" "$FW/uwe5621ds/wcnmodem_2ant.bin"
sudo install -m 644 "$UWE_ASSETS/wifi_56630001_2ant.ini" "$FW/uwe5621ds/wifi_56630001_2ant.ini"
sudo install -m 644 "$UWE_ASSETS/wifi_56630001_3ant.ini" "$FW/uwe5621ds/wifi_56630001_3ant.ini"
sudo install -m 644 "$UWE_ASSETS/wifi_56630001_2ant.ini" "$FW/wifi_56630001_2ant.ini"
sudo install -m 644 "$UWE_ASSETS/wifi_56630001_3ant.ini" "$FW/wifi_56630001_3ant.ini"
sudo install -m 644 "$UWE_ASSETS/bt_configure_pskey.ini" "$FW/bt_configure_pskey.ini"
sudo install -m 644 "$UWE_ASSETS/bt_configure_rf.ini" "$FW/bt_configure_rf.ini"
sudo install -m 644 "$UWE_ASSETS/bt_configure_rf_marlin3e_2.ini" "$FW/bt_configure_rf_marlin3e_2.ini"
sudo install -m 644 "$UWE_ASSETS/bt_configure_rf_marlin3e_3.ini" "$FW/bt_configure_rf_marlin3e_3.ini"
sudo install -m 755 "$UWE_ASSETS/hciattach_opi_arm64" "$TMPDIR/usr/bin/hciattach_opi"
sudo install -m 755 "$UWE_ASSETS/torder-tablet-bluetooth" "$TMPDIR/usr/bin/torder-tablet-bluetooth"
sudo install -m 644 "$UWE_ASSETS/torder-tablet-bluetooth.service" "$TMPDIR/usr/lib/systemd/system/torder-tablet-bluetooth.service"
sudo mkdir -p "$TMPDIR/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /usr/lib/systemd/system/torder-tablet-bluetooth.service "$TMPDIR/etc/systemd/system/multi-user.target.wants/torder-tablet-bluetooth.service"
echo "UWE5621DS WiFi and Bluetooth assets installed"

# ============================================================
# 7. Runtime performance policy
# ============================================================
sudo mkdir -p "$TMPDIR/usr/local/sbin" "$TMPDIR/etc/systemd/system" "$TMPDIR/etc/sysctl.d" "$TMPDIR/etc/dconf/db/local.d"
sudo tee "$TMPDIR/usr/local/sbin/torder-performance" > /dev/null << 'PERFSCRIPTEOF'
#!/bin/sh
set -eu

set_governor() {
    governor_file="$1"
    available_file="${governor_file%/governor}/available_governors"
    [ -w "$governor_file" ] || return 0
    if [ -r "$available_file" ] && grep -qw performance "$available_file"; then
        echo performance > "$governor_file"
    fi
}

for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$policy" ] || continue
    set_governor "$policy/scaling_governor"
done

for governor in /sys/class/devfreq/*/governor; do
    [ -e "$governor" ] || continue
    set_governor "$governor"
done
PERFSCRIPTEOF
sudo chmod 755 "$TMPDIR/usr/local/sbin/torder-performance"

sudo tee "$TMPDIR/etc/systemd/system/torder-performance.service" > /dev/null << 'PERFSERVICEEOF'
[Unit]
Description=Torder Tablet maximum performance policy
After=systemd-modules-load.service
Before=graphical.target display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/torder-performance
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
PERFSERVICEEOF
sudo mkdir -p "$TMPDIR/etc/systemd/system/multi-user.target.wants"
sudo ln -sf ../torder-performance.service "$TMPDIR/etc/systemd/system/multi-user.target.wants/torder-performance.service"

sudo tee "$TMPDIR/etc/sysctl.d/90-torder-performance.conf" > /dev/null << 'SYSCTLEOF'
vm.swappiness=60
vm.page-cluster=0
vm.vfs_cache_pressure=50
SYSCTLEOF

sudo tee "$TMPDIR/etc/dconf/db/local.d/02-torder-performance" > /dev/null << 'DCONFEOF'
[org/gnome/desktop/interface]
enable-animations=false

[org/gnome/software]
download-updates=false
DCONFEOF
sudo chroot "$TMPDIR" dconf update 2>/dev/null || true

for svc in packagekit.service packagekit-offline-update.service fwupd.service; do
    sudo chroot "$TMPDIR" systemctl mask "$svc" 2>/dev/null || true
done
echo "Maximum runtime performance policy installed"

# ============================================================
# 8. Power key lock screen, backlight, and touch wake
# ============================================================
sudo mkdir -p "$TMPDIR/usr/local/sbin" "$TMPDIR/etc/systemd/system" "$TMPDIR/etc/systemd/logind.conf.d"
sudo tee "$TMPDIR/usr/local/sbin/powerkey-backlight-toggle.py" > /dev/null << 'PYSCRIPTEOF'
#!/usr/bin/env python3
import glob
import os
import select
import struct
import subprocess
import sys
import time

KEY_POWER = 116
EV_KEY = 1
BACKLIGHT_DIR = "/sys/class/backlight/backlight"
STATE_FILE = "/run/powerkey-backlight-toggle.brightness"
DEFAULT_RESTORE = 80
DEBOUNCE_SECONDS = 0.3
TOUCH_POWER_CONTROLS = [
    "/sys/devices/platform/fe5a0000.i2c/power/control",
    "/sys/devices/platform/fe5a0000.i2c/i2c-1/1-0040/power/control",
    "/sys/devices/platform/fe5a0000.i2c/i2c-1/1-0040/input/input2/power/control",
    "/sys/devices/platform/fe5a0000.i2c/i2c-1/1-0040/input/input2/event2/power/control",
]


def find_power_device():
    preferred = sorted(glob.glob("/dev/input/by-path/*rk805-pwrkey-event"))
    preferred += sorted(glob.glob("/dev/input/by-path/*pwrkey-event"))
    for path in preferred:
        return path
    for path in sorted(glob.glob("/dev/input/event*")):
        try:
            event = os.path.basename(path)
            with open(f"/sys/class/input/{event}/device/name") as f:
                name = f.read().strip().lower()
            if "pwrkey" in name or "power" in name:
                return path
        except OSError:
            pass
    raise FileNotFoundError("power key input device not found")


def read_int(path, default=0):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except Exception:
        return default


def write_value(path, value):
    try:
        with open(path, "w") as f:
            f.write(str(value))
    except OSError as exc:
        print(f"failed to write {path}: {exc}", file=sys.stderr, flush=True)


def keep_touch_power_on():
    for path in TOUCH_POWER_CONTROLS:
        try:
            with open(path, "w") as f:
                f.write("on")
        except OSError:
            pass


def max_brightness():
    return max(1, read_int(os.path.join(BACKLIGHT_DIR, "max_brightness"), 255))


def brightness():
    return read_int(os.path.join(BACKLIGHT_DIR, "brightness"), 0)


def bl_power():
    return read_int(os.path.join(BACKLIGHT_DIR, "bl_power"), 0)


def save_brightness(value):
    value = max(1, min(value, max_brightness()))
    with open(STATE_FILE, "w") as f:
        f.write(str(value))


def restore_backlight():
    keep_touch_power_on()
    value = read_int(STATE_FILE, DEFAULT_RESTORE)
    value = max(1, min(value, max_brightness()))
    write_value(os.path.join(BACKLIGHT_DIR, "bl_power"), 0)
    write_value(os.path.join(BACKLIGHT_DIR, "brightness"), value)
    keep_touch_power_on()
    print(f"restored backlight to {value}", flush=True)


def lock_user_sessions():
    try:
        out = subprocess.check_output(["/usr/bin/loginctl", "list-sessions", "--no-legend"], text=True)
    except Exception as exc:
        print(f"failed to list sessions: {exc}", file=sys.stderr, flush=True)
        return
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1] == "1000":
            subprocess.run(["/usr/bin/loginctl", "lock-session", parts[0]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print(f"locked session {parts[0]}", flush=True)


def blank_backlight():
    keep_touch_power_on()
    before = brightness()
    if before > 0:
        save_brightness(before)
    lock_user_sessions()
    write_value(os.path.join(BACKLIGHT_DIR, "bl_power"), 0)
    write_value(os.path.join(BACKLIGHT_DIR, "brightness"), 0)
    keep_touch_power_on()
    print("blanked backlight", flush=True)


def toggle_backlight():
    if brightness() <= 0 or bl_power() != 0:
        restore_backlight()
    else:
        blank_backlight()


def main():
    keep_touch_power_on()
    device = find_power_device()
    event_struct = struct.Struct("llHHi")
    last_press = 0.0
    print(f"listening on {device}", flush=True)
    with open(device, "rb", buffering=0) as dev:
        poller = select.poll()
        poller.register(dev, select.POLLIN)
        while True:
            poller.poll()
            data = dev.read(event_struct.size)
            if len(data) != event_struct.size:
                continue
            _sec, _usec, ev_type, code, value = event_struct.unpack(data)
            if ev_type == EV_KEY and code == KEY_POWER and value == 1:
                now = time.monotonic()
                if now - last_press >= DEBOUNCE_SECONDS:
                    last_press = now
                    toggle_backlight()


if __name__ == "__main__":
    main()

PYSCRIPTEOF
sudo chmod 755 "$TMPDIR/usr/local/sbin/powerkey-backlight-toggle.py"

sudo tee "$TMPDIR/etc/systemd/system/powerkey-backlight-toggle.service" > /dev/null << 'SVCEOF'
[Unit]
Description=Power key lock screen, backlight, and touch wake handler
After=systemd-logind.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/powerkey-backlight-toggle.py
Restart=always
RestartSec=1

[Install]
WantedBy=graphical.target
SVCEOF
sudo chroot "$TMPDIR" systemctl enable powerkey-backlight-toggle.service 2>/dev/null || true
sudo mkdir -p "$TMPDIR/etc/systemd/system/graphical.target.wants"
sudo ln -sf ../powerkey-backlight-toggle.service "$TMPDIR/etc/systemd/system/graphical.target.wants/powerkey-backlight-toggle.service"

sudo tee "$TMPDIR/etc/systemd/logind.conf.d/90-powerkey-lock.conf" > /dev/null << 'LOGIND'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore
LOGIND


sudo mkdir -p "$TMPDIR/etc/udev/rules.d"
sudo tee "$TMPDIR/etc/udev/rules.d/99-touch-no-runtime-pm.rules" > /dev/null << 'UDEV'
ACTION=="add|change", SUBSYSTEM=="i2c", KERNEL=="1-0040", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add|change", SUBSYSTEM=="input", ATTR{name}=="gsl3673_800x1280", TEST=="power/control", ATTR{power/control}="on"
UDEV

echo "powerkey-backlight-toggle installed"

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
grep HandlePowerKey "$TMPDIR/etc/systemd/logind.conf.d/90-powerkey-lock.conf"
cat "$TMPDIR/etc/modules-load.d/touchscreen.conf"
ls "$TMPDIR/usr/local/sbin/powerkey-backlight-toggle.py"
ls "$TMPDIR/etc/systemd/system/powerkey-backlight-toggle.service"
ls "$TMPDIR/etc/systemd/logind.conf.d/90-powerkey-lock.conf"
ls "$TMPDIR/etc/udev/rules.d/99-touch-no-runtime-pm.rules"
ls "$TMPDIR/lib/firmware/uwe5621ds/wcnmodem_2ant.bin"
ls "$TMPDIR/lib/firmware/wifi_56630001_3ant.ini"
ls "$TMPDIR/usr/bin/hciattach_opi"
ls "$TMPDIR/usr/local/sbin/torder-tablet-bluetooth"
ls "$TMPDIR/usr/lib/systemd/system/torder-tablet-bluetooth.service"

# Cleanup
sudo umount "$TMPDIR/dev" "$TMPDIR/proc" "$TMPDIR/sys" 2>/dev/null || true
sudo umount "$TMPDIR"
sudo losetup -d "$LOOP"
rmdir "$TMPDIR"

# GPT partition name
sudo sfdisk --part-name "$IMG" 1 rootfs 2>/dev/null || echo "sfdisk will fix at runtime"

echo "Post-build complete!"
