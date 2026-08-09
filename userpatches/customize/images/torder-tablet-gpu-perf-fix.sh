#!/bin/bash
#
# Torder Tablet - GPU & Performance Optimization
#
# Fixes:
# 1. Panfrost GPU driver configuration
# 2. CPU/GPU max performance mode
# 3. GNOME optimization (disable Tracker, animations, heavy services)
# 4. ZRAM swap setup
#
# Runs during image build after rootfs is assembled.
#

display_alert "Torder Tablet" "Applying GPU & performance optimizations" "info"

# ============================================================
# Fix 1: Panfrost GPU X11/Wayland configuration
# ============================================================
XORG_CONF="${SDCARD}/etc/X11/xorg.conf.d/20-panfrost.conf"
mkdir -p "$(dirname "${XORG_CONF}")"
cat > "${XORG_CONF}" << 'EOF'
Section "Device"
    Identifier "GPU"
    Driver "modesetting"
    Option "DRI" "3"
    Option "AccelMethod" "glamor"
    Option "PageFlip" "on"
EndSection

Section "ServerFlags"
    Option "Debug" "dmabuf_capable"
EndSection
EOF
display_alert "Torder Tablet" "Created Panfrost X11 configuration" "info"

# ============================================================
# Fix 2: Max Performance systemd service (CPU + GPU)
# ============================================================
cat > "${SDCARD}/etc/systemd/system/max-performance.service" << 'EOF'
[Unit]
Description=Max Performance Mode
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "for i in 0 1 2 3; do echo performance > /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor; echo 1800000 > /sys/devices/system/cpu/cpu$i/cpufreq/scaling_min_freq; done; echo performance > /sys/class/devfreq/fde60000.gpu/governor; echo 800000000 > /sys/class/devfreq/fde60000.gpu/min_freq"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
# Enable the service (will run on first boot via chroot)
chroot "${SDCARD}" /bin/bash -c "systemctl enable max-performance.service 2>/dev/null" || true
display_alert "Torder Tablet" "Created max-performance.service" "info"

# ============================================================
# Fix 3: ZRAM swap service
# ============================================================
cat > "${SDCARD}/etc/systemd/system/zram-swap.service" << 'EOF'
[Unit]
Description=Setup ZRAM Swap
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "modprobe zram; echo lz4 > /sys/block/zram0/comp_algorithm; echo 1G > /sys/block/zram0/disksize; mkswap /dev/zram0; swapon -p 100 /sys/block/zram0"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
chroot "${SDCARD}" /bin/bash -c "systemctl enable zram-swap.service 2>/dev/null" || true
display_alert "Torder Tablet" "Created zram-swap.service" "info"

# ============================================================
# Fix 4: Disable heavy GNOME services
# ============================================================
# Create a first-login script to apply GNOME optimizations
FIRST_LOGIN="${SDCARD}/etc/armbian_first_login.d/99-torder-optimize.sh"
mkdir -p "$(dirname "${FIRST_LOGIN}")"
cat > "${FIRST_LOGIN}" << 'OPTIMIZE'
#!/bin/bash
#
# Torder Tablet - GNOME optimization on first login
#
# Only runs for the first user created during setup

if [ "$(id -u)" -eq 1000 ]; then
    # Disable Tracker file indexing
    gsettings set org.freedesktop.Tracker3.Miner.Files crawling-interval -2 2>/dev/null || true
    gsettings set org.freedesktop.Tracker3.Miner.Files enable-monitors false 2>/dev/null || true

    # Avoid compositor work on the tablet GPU.
    gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.preferences audible-bell false 2>/dev/null || true

    # Disable GNOME search providers
    gsettings set org.gnome.desktop.search-providers disable-all true 2>/dev/null || true

    # Disable auto updates
    gsettings set org.gnome.software download-updates false 2>/dev/null || true

    # Disable transparency on dash-to-dock (if extension exists)
    gsettings set org.gnome.Shell.extensions.dash-to-dock transparency-mode FIXED 2>/dev/null || true
    gsettings set org.gnome.Shell.extensions.dash-to-dock dash-max-icon-size 32 2>/dev/null || true
fi
OPTIMIZE
chmod +x "${FIRST_LOGIN}"
display_alert "Torder Tablet" "Created GNOME first-login optimization script" "info"

# ============================================================
# Fix 5: Disable heavy systemd services globally
# ============================================================
for svc in \
    cups.service \
    cups-browsed.service \
    unattended-upgrades.service; do
    chroot "${SDCARD}" /bin/bash -c "systemctl mask ${svc} 2>/dev/null" || true
done
display_alert "Torder Tablet" "Masked heavy services (cups, unattended-upgrades)" "info"

# ============================================================
# Fix 6: Disable Tracker at system level
# ============================================================
TRACKER_CONF="${SDCARD}/etc/xdg/autostart/tracker-miner-fs-3.desktop"
if [ -f "${TRACKER_CONF}" ]; then
    echo "Hidden=true" >> "${TRACKER_CONF}"
    display_alert "Torder Tablet" "Disabled Tracker autostart" "info"
fi

TRACKER_EXTRACT="${SDCARD}/etc/xdg/autostart/tracker-extract-3.desktop"
if [ -f "${TRACKER_EXTRACT}" ]; then
    echo "Hidden=true" >> "${TRACKER_EXTRACT}"
fi

# ============================================================
# Fix 7: Power button lock screen, backlight, and touch wake
# ============================================================
mkdir -p "${SDCARD}/usr/local/sbin" "${SDCARD}/etc/systemd/system" "${SDCARD}/etc/systemd/logind.conf.d"
cat > "${SDCARD}/usr/local/sbin/powerkey-backlight-toggle.py" << 'PWREOF'
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

PWREOF
chmod 755 "${SDCARD}/usr/local/sbin/powerkey-backlight-toggle.py"

cat > "${SDCARD}/etc/systemd/system/powerkey-backlight-toggle.service" << 'SVCEOF'
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
chroot "${SDCARD}" /bin/bash -c "systemctl enable powerkey-backlight-toggle.service 2>/dev/null" || true
mkdir -p "${SDCARD}/etc/systemd/system/graphical.target.wants"
ln -sf ../powerkey-backlight-toggle.service "${SDCARD}/etc/systemd/system/graphical.target.wants/powerkey-backlight-toggle.service"

cat > "${SDCARD}/etc/systemd/logind.conf.d/90-powerkey-lock.conf" << 'LOGIND'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore
LOGIND


mkdir -p "${SDCARD}/etc/udev/rules.d"
cat > "${SDCARD}/etc/udev/rules.d/99-touch-no-runtime-pm.rules" << 'UDEV'
ACTION=="add|change", SUBSYSTEM=="i2c", KERNEL=="1-0040", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add|change", SUBSYSTEM=="input", ATTR{name}=="gsl3673_800x1280", TEST=="power/control", ATTR{power/control}="on"
UDEV

display_alert "Torder Tablet" "Power button lock screen, backlight, and touch wake configured" "info"

display_alert "Torder Tablet" "GPU & performance optimizations applied" "info"
