#!/bin/bash
# Post-build: install the board DTB, boot settings, hardware assets, and services.
set -euo pipefail

WORK="${1:?Usage: post-build.sh IMAGE_DIRECTORY [IMAGE]}"
IMG="${2:-}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
UWE_ASSETS="$SCRIPT_DIR/../assets/uwe5621ds"
DISPLAY_ASSETS="$SCRIPT_DIR/../assets/display"
MPP_ROOTFS="${ROCKCHIP_MPP_ROOTFS:-}"
MPP_COMMIT="${ROCKCHIP_MPP_COMMIT:-unknown}"
RKNPU_ROOTFS="${RKNPU_ROOTFS:-}"
RKNN_COMMIT="${RKNN_TOOLKIT_COMMIT:-unknown}"
SNAP_CONFINE_CAPS="cap_chown,cap_dac_override,cap_dac_read_search,cap_fowner,cap_setgid,cap_setuid,cap_sys_chroot,cap_sys_ptrace,cap_sys_admin,cap_sys_resource=p"
KERNEL_VERSION="6.1.115-vendor-rk35xx"
UWE5621DS_SOURCE_COMMIT="4c63dfbe1e860c45a7c5e326cddd1a87f44e4fb3"
UWE5621DS_SRCVERSION="50D3A59AC5058B3C5B7E57D"
UWE5621DS_2ANT_INI_SHA256="7daa38ae65de45f47d21d9a381dfef295930ebd0c4a335dfed908075e03747d8"
UWE5621DS_3ANT_INI_SHA256="66650cf7682c767a10399020e5294b74da233cdffee20310cdb005ae43b79b9f"
UWE5621DS_WCN_SHA256="9aa13de426be49f5748506279796f6eddc3479af9d5bd9568170742f542e3605"
LOOP=""
TMPDIR=""
VERIFY_DIR=""
DIAGNOSTICS="$WORK/uwe5621ds-diagnostics.txt"

cleanup() {
    local status=$?
    set +e
    if [ "$status" -ne 0 ] && [ -n "${DIAGNOSTICS:-}" ]; then
        printf 'result=FAIL exit_status=%s\n' "$status" >> "$DIAGNOSTICS" 2>/dev/null || true
    fi
    if [ -n "${TMPDIR:-}" ]; then
        for path in "$TMPDIR/dev" "$TMPDIR/proc" "$TMPDIR/sys"; do
            mountpoint -q "$path" && sudo umount "$path"
        done
        mountpoint -q "$TMPDIR" && sudo umount "$TMPDIR"
        rmdir "$TMPDIR" 2>/dev/null || true
    fi
    if [ -n "${LOOP:-}" ]; then
        sudo losetup -d "$LOOP" 2>/dev/null || true
    fi
    if [ -n "${VERIFY_DIR:-}" ] && [ -d "$VERIFY_DIR" ]; then
        rm -rf -- "$VERIFY_DIR"
    fi
    TMPDIR=""
    LOOP=""
    VERIFY_DIR=""
    set -e
    return "$status"
}

trap cleanup EXIT

if [ -z "$IMG" ]; then
    IMG=$(find "$WORK" -name "*.img" -not -name "*.img.*" -print -quit)
fi

test -n "$IMG"
test -f "$IMG"

cat > "$DIAGNOSTICS" << EOF
UWE5621DS image diagnostics
driver_source_commit=$UWE5621DS_SOURCE_COMMIT
driver_srcversion=$UWE5621DS_SRCVERSION
kernel_version=$KERNEL_VERSION
image=$IMG
EOF

echo "Image: $IMG"

DTB_SRC="$WORK/../../userpatches/dtb/rockchip/rk3566-torder-tablet.dtb"
if [ ! -f "$DTB_SRC" ]; then
    DTB_SRC="$WORK/../../../../TorderTable-Armbian/dtb/rockchip/rk3566-torder-tablet.dtb"
fi
test -f "$DTB_SRC"
command -v fdtget > /dev/null
command -v fdtput > /dev/null

LOOP=$(sudo losetup -fP --show "$IMG")
sleep 1
TMPDIR=$(mktemp -d)
sudo mount "${LOOP}p1" "$TMPDIR"
echo "Mounted at $TMPDIR"

test -n "$MPP_ROOTFS"
test -x "$MPP_ROOTFS/usr/bin/mpi_enc_test"
test -x "$MPP_ROOTFS/usr/bin/mpi_dec_test"
sudo cp -a "$MPP_ROOTFS/usr/." "$TMPDIR/usr/"
test -n "$RKNPU_ROOTFS"
test -x "$RKNPU_ROOTFS/usr/bin/rknn-smoke-test"
test -f "$RKNPU_ROOTFS/usr/lib/aarch64-linux-gnu/librknnrt.so"
sudo cp -a "$RKNPU_ROOTFS/usr/." "$TMPDIR/usr/"
sudo ldconfig -r "$TMPDIR"

# Ubuntu's Chromium package is a Snap launcher. Keep the complete ARM64 Snap
# payload in the image so Chromium is available without a first-boot download.
BUNDLED_SNAP_CACHE="$TMPDIR/var/cache/torder-bundled-snaps"
sudo mkdir -p "$BUNDLED_SNAP_CACHE"
for snap_revision in \
    bare:5 \
    core22:2438 \
    core24:1644 \
    gtk-common-themes:1535 \
    mesa-2404:1836 \
    gnome-46-2404:154 \
    cups:1237 \
    chromium:3506 \
    snap-store:1391; do
    snap_name=${snap_revision%%:*}
    revision=${snap_revision##*:}
    sudo chroot "$TMPDIR" snap download "$snap_name" \
        --revision="$revision" \
        --basename="${snap_name}_${revision}" \
        --target-directory=/var/cache/torder-bundled-snaps
done

sudo install -m 755 /dev/stdin \
    "$TMPDIR/usr/local/sbin/torder-install-bundled-snaps" << 'BUNDLED_SNAPS_INSTALL'
#!/bin/bash
set -euo pipefail

CACHE=/var/cache/torder-bundled-snaps
SNAPS=(
    bare:5
    core22:2438
    core24:1644
    gtk-common-themes:1535
    mesa-2404:1836
    gnome-46-2404:154
    cups:1237
    chromium:3506
    snap-store:1391
)

if snap list chromium > /dev/null 2>&1 && \
        snap list snap-store > /dev/null 2>&1; then
    rm -rf -- "$CACHE"
    exit 0
fi

for snap_revision in "${SNAPS[@]}"; do
    snap_name=${snap_revision%%:*}
    revision=${snap_revision##*:}
    snap ack "$CACHE/${snap_name}_${revision}.assert" 2>/dev/null || true
    if ! snap list "$snap_name" > /dev/null 2>&1; then
        snap install "$CACHE/${snap_name}_${revision}.snap"
    fi
done

snap switch chromium --channel=latest/stable
snap switch snap-store --channel=2/stable
snap connect chromium:password-manager-service 2>/dev/null || true
snap list chromium
snap list snap-store
rm -rf -- "$CACHE"
BUNDLED_SNAPS_INSTALL

sudo install -m 644 /dev/stdin \
    "$TMPDIR/etc/systemd/system/torder-install-bundled-snaps.service" << 'BUNDLED_SNAPS_SERVICE'
[Unit]
Description=Install bundled Chromium and Snap Store
Wants=snapd.service
After=snapd.service snapd.socket
Before=display-manager.service
ConditionPathExists=/var/cache/torder-bundled-snaps/chromium_3506.snap

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/torder-install-bundled-snaps
TimeoutStartSec=15min

[Install]
WantedBy=graphical.target
BUNDLED_SNAPS_SERVICE

sudo mkdir -p "$TMPDIR/etc/systemd/system/graphical.target.wants"
sudo ln -sf ../torder-install-bundled-snaps.service \
    "$TMPDIR/etc/systemd/system/graphical.target.wants/torder-install-bundled-snaps.service"

# PulseAudio's generic RK817 fallback profile can restore the headphone enum
# even when its active port is Speakers. Apply the board's final codec route
# after the per-user audio server starts. The low-level spk switch is left to
# RK817 DAPM so it can power the amplifier down between streams.
sudo install -m 644 /dev/stdin \
    "$TMPDIR/usr/lib/systemd/user/torder-speaker-route.service" << 'SPEAKER_ROUTE_SERVICE'
[Unit]
Description=Select the RK817 internal speaker route
After=pulseaudio.service pipewire.service
ConditionPathExists=/dev/snd/controlC0

[Service]
Type=oneshot
ExecStart=/usr/bin/amixer -c 0 sset 'Playback Path' SPK
ExecStart=/usr/bin/amixer -c 0 sset Speaker on
RemainAfterExit=yes

[Install]
WantedBy=default.target
SPEAKER_ROUTE_SERVICE

sudo mkdir -p "$TMPDIR/etc/systemd/user/default.target.wants"
sudo ln -sf /usr/lib/systemd/user/torder-speaker-route.service \
    "$TMPDIR/etc/systemd/user/default.target.wants/torder-speaker-route.service"

ROOT_UUID=$(sudo blkid -s UUID -o value "${LOOP}p1")
if ! [[ "$ROOT_UUID" =~ ^[0-9A-Fa-f-]+$ ]]; then
    echo "Invalid root filesystem UUID: $ROOT_UUID" >&2
    exit 1
fi
echo "Root filesystem UUID: $ROOT_UUID"

# First-boot GPT expansion can replace the root partition and change its
# PARTUUID/PARTLABEL. Keep every persistent root reference on the ext4 UUID and
# normalize malformed duplicate commas in the generated mount options.
FSTAB_FIXED=$(mktemp)
if ! awk -v uuid="$ROOT_UUID" '
    BEGIN { OFS = " "; roots = 0 }
    $0 !~ /^[[:space:]]*#/ && $2 == "/" {
        $1 = "UUID=" uuid
        gsub(/,+/, ",", $4)
        roots++
    }
    { print }
    END { if (roots != 1) exit 1 }
' "$TMPDIR/etc/fstab" > "$FSTAB_FIXED"; then
    rm -f "$FSTAB_FIXED"
    echo "Expected exactly one root entry in fstab" >&2
    exit 1
fi
sudo install -m 644 "$FSTAB_FIXED" "$TMPDIR/etc/fstab"
rm -f "$FSTAB_FIXED"
echo "Root fstab entry pinned to filesystem UUID"

# ============================================================
# 1. DTB
# ============================================================
sudo mkdir -p "$TMPDIR/boot/dtb/rockchip"
sudo mkdir -p "$TMPDIR/boot/dtb-6.1.115-vendor-rk35xx/rockchip"
for DTB_DST in \
    "$TMPDIR/boot/dtb/rockchip/rk3566-torder-tablet.dtb" \
    "$TMPDIR/boot/dtb-6.1.115-vendor-rk35xx/rockchip/rk3566-torder-tablet.dtb"; do
    sudo install -m 644 "$DTB_SRC" "$DTB_DST"
    BOOTARGS=$(sudo fdtget -t s "$DTB_DST" /chosen bootargs)
    PATCHED_BOOTARGS=$(printf '%s\n' "$BOOTARGS" | sed -E "s#(^|[[:space:]])root=[^[:space:]]+#\\1root=UUID=$ROOT_UUID#")
    if [ "$PATCHED_BOOTARGS" = "$BOOTARGS" ]; then
        echo "DTB bootargs does not contain a root= argument: $DTB_DST" >&2
        exit 1
    fi
    sudo fdtput -t s "$DTB_DST" /chosen bootargs "$PATCHED_BOOTARGS"
    sudo fdtget -t s "$DTB_DST" /chosen bootargs | grep -F "root=UUID=$ROOT_UUID"
    test "$(sudo fdtget -t u "$DTB_DST" \
        /dsi@fe060000/panel@0/display-timings/timing0 clock-frequency)" = \
        "101147760"
done
echo "DTB installed with filesystem UUID root and 90Hz panel timing"

# Panthor overlay
sudo mkdir -p "$TMPDIR/boot/dtb/rockchip/overlay"
sudo mkdir -p "$TMPDIR/boot/dtb-6.1.115-vendor-rk35xx/rockchip/overlay"
PANTHOR=$(find "$TMPDIR/boot/dtb-6.1.115-vendor-rk35xx/rockchip/overlay/" -name "*panthor*" -print -quit 2>/dev/null)
if [ -n "$PANTHOR" ]; then
    sudo cp "$PANTHOR" "$TMPDIR/boot/dtb/rockchip/overlay/" 2>/dev/null || true
    echo "Panthor overlay copied"
fi

# ============================================================
# 2. armbianEnv.txt
# ============================================================
sudo tee "$TMPDIR/boot/armbianEnv.txt" > /dev/null << EOF
verbosity=1
bootlogo=true
console=both
extraargs=cma=256M
overlay_prefix=rk35xx
overlays=panthor-gpu
fdtfile=rockchip/rk3566-torder-tablet.dtb
rootdev=UUID=$ROOT_UUID
rootfstype=ext4
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
EOF
echo "armbianEnv.txt set"

# ============================================================
# 3. Touchscreen auto-load
# ============================================================
sudo mkdir -p "$TMPDIR/etc/modules-load.d"
echo "gsl3673-800x1280" | sudo tee "$TMPDIR/etc/modules-load.d/touchscreen.conf" > /dev/null
if ! grep -q "gsl3673-800x1280" "$TMPDIR/etc/modules" 2>/dev/null; then
    echo "gsl3673-800x1280" | sudo tee -a "$TMPDIR/etc/modules" > /dev/null
fi
echo "Touchscreen auto-load configured"

# ============================================================
# 4. WiFi and Bluetooth
# ============================================================
for file in hciattach_opi_arm64 wcnmodem.bin wcnmodem_2ant.bin \
    wifi_56630001_2ant.ini wifi_56630001_3ant.ini bt_configure_pskey.ini \
    bt_configure_rf.ini bt_configure_rf_marlin3e_2.ini bt_configure_rf_marlin3e_3.ini \
    torder-tablet-bluetooth torder-tablet-bluetooth.service \
    torder-wifi-mac torder-wifi-mac.service 90-torder-wifi.conf; do
    test -f "$UWE_ASSETS/$file"
done

FW="$TMPDIR/lib/firmware"
sudo install -d "$FW/uwe5621ds" "$TMPDIR/usr/bin" "$TMPDIR/usr/local/sbin" \
    "$TMPDIR/usr/lib/systemd/system" "$TMPDIR/etc/systemd/system" \
    "$TMPDIR/etc/systemd/system/sysinit.target.wants" "$TMPDIR/etc/NetworkManager/conf.d"
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

# Never ship a captured factory MAC. Generate a stable per-device address before
# udev or modules can probe sprdwl_ng on first boot.
sudo rm -f "$FW/unisoc_wifi_mac.txt"
sudo install -m 755 "$UWE_ASSETS/torder-wifi-mac" "$TMPDIR/usr/local/sbin/torder-wifi-mac"
sudo install -m 644 "$UWE_ASSETS/torder-wifi-mac.service" "$TMPDIR/etc/systemd/system/torder-wifi-mac.service"
sudo ln -sf ../torder-wifi-mac.service "$TMPDIR/etc/systemd/system/sysinit.target.wants/torder-wifi-mac.service"

# The driver can run an AP but cannot set the default IGTK required by optional
# PMF. NetworkManager must create WPA2 hotspots without PMF on this device.
sudo install -m 644 "$UWE_ASSETS/90-torder-wifi.conf" "$TMPDIR/etc/NetworkManager/conf.d/90-torder-wifi.conf"

echo "UWE5621DS WiFi and Bluetooth assets installed"

# GNOME reports Night Light as active on X11, but this VOP stack does not
# reliably retain the color LUT. Keep its D-Bus state applied through RandR.
test -f "$DISPLAY_ASSETS/torder-night-light.py"
test -f "$DISPLAY_ASSETS/torder-night-light.service"
sudo install -d "$TMPDIR/usr/local/bin" "$TMPDIR/usr/lib/systemd/user" \
    "$TMPDIR/etc/systemd/user/default.target.wants"
sudo install -m 755 "$DISPLAY_ASSETS/torder-night-light.py" \
    "$TMPDIR/usr/local/bin/torder-night-light"
sudo install -m 644 "$DISPLAY_ASSETS/torder-night-light.service" \
    "$TMPDIR/usr/lib/systemd/user/torder-night-light.service"
sudo ln -sf /usr/lib/systemd/user/torder-night-light.service \
    "$TMPDIR/etc/systemd/user/default.target.wants/torder-night-light.service"
echo "X11 Night Light fallback installed"

# ============================================================
# 5. Runtime performance policy
# ============================================================
sudo mkdir -p "$TMPDIR/usr/local/sbin" "$TMPDIR/etc/systemd/system" "$TMPDIR/etc/sysctl.d" "$TMPDIR/etc/dconf/db/local.d"
sudo tee "$TMPDIR/usr/local/sbin/torder-performance" > /dev/null << 'PERFSCRIPTEOF'
#!/bin/sh
set -eu

set_governor() {
    governor_file="$1"
    available_file="$2"
    [ -w "$governor_file" ] || return 0
    if [ -r "$available_file" ] && grep -qw performance "$available_file"; then
        echo performance > "$governor_file"
    fi
}

for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$policy" ] || continue
    set_governor "$policy/scaling_governor" "$policy/scaling_available_governors"
done

for governor in /sys/class/devfreq/*/governor; do
    [ -e "$governor" ] || continue
    set_governor "$governor" "${governor%/governor}/available_governors"
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

[org/gnome/settings-daemon/plugins/color]
night-light-temperature=uint32 4000
DCONFEOF
sudo chroot "$TMPDIR" dconf update 2>/dev/null || true

for svc in packagekit.service packagekit-offline-update.service fwupd.service; do
    sudo chroot "$TMPDIR" systemctl mask "$svc" 2>/dev/null || true
done
echo "Maximum runtime performance policy installed"

# ============================================================
# 6. Power key lock screen, backlight, and touch wake
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
sudo tee "$TMPDIR/etc/udev/rules.d/99-rockchip-media.rules" > /dev/null << 'UDEV'
KERNEL=="mpp_service", GROUP="render", MODE="0660", TAG+="uaccess"
KERNEL=="rga", GROUP="render", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="dma_heap", GROUP="render", MODE="0660", TAG+="uaccess"
UDEV

echo "powerkey-backlight-toggle installed"

# ============================================================
# 7. GNOME power button = nothing (no shutdown dialog)
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
# 8. depmod
# ============================================================
sudo chroot "$TMPDIR" depmod -a "$KERNEL_VERSION" 2>/dev/null || true
echo "depmod done"

# ============================================================
# 9. GDM autologin
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

# snap-confine is intentionally capability-based on Ubuntu Noble. Reapply the
# package capabilities after all image transformations and fail closed if any
# required privilege is missing.
SNAP_CONFINE="$TMPDIR/usr/lib/snapd/snap-confine"
test -x "$SNAP_CONFINE"
command -v setcap > /dev/null
command -v getcap > /dev/null
sudo setcap "$SNAP_CONFINE_CAPS" "$SNAP_CONFINE"
SNAP_CONFINE_ACTUAL=$(getcap -n "$SNAP_CONFINE")
for capability in \
    cap_dac_override \
    cap_dac_read_search \
    cap_setgid \
    cap_setuid \
    cap_sys_admin \
    cap_sys_chroot; do
    grep -F "$capability" <<< "$SNAP_CONFINE_ACTUAL" > /dev/null
done
printf 'snap-confine capabilities: %s\n' "$SNAP_CONFINE_ACTUAL"

grep -Fx "rootdev=UUID=$ROOT_UUID" "$TMPDIR/boot/armbianEnv.txt"
awk -v root="UUID=$ROOT_UUID" '
    $0 !~ /^[[:space:]]*#/ && $2 == "/" && $1 == root && $4 !~ /,,/ { roots++ }
    END { exit roots == 1 ? 0 : 1 }
' "$TMPDIR/etc/fstab"
KERNEL_CONFIG=$(find "$TMPDIR/boot" -maxdepth 1 -type f -name 'config-*-vendor-rk35xx' -print -quit)
test -n "$KERNEL_CONFIG"
grep -Eq '^CONFIG_CC_VERSION_TEXT="aarch64-linux-gnu-gcc .* 11\.4\.0"$' "$KERNEL_CONFIG"
for option in \
    'CONFIG_GCC_VERSION=110400' \
    'CONFIG_WCN_BSP_DRIVER_BUILDIN=y' \
    'CONFIG_RK_WIFI_DEVICE_UWE5621=y' \
    'CONFIG_RK_WIFI_DEVICE_UWE5622=y' \
    'CONFIG_WLAN_UWE5621=m' \
    'CONFIG_WLAN_UWE5622=m' \
    'CONFIG_SPRDWL_NG=m' \
    'CONFIG_TTY_OVERY_SDIO=m' \
    '# CONFIG_WIFI_GENERATE_RANDOM_MAC_ADDR is not set'; do
    grep -Fx "$option" "$KERNEL_CONFIG"
done

# The working image builds the shared WCN BSP into vmlinux. sprdwl_ng must not
# depend on a second BSP module, which probes the same bus channels twice and
# leaves a non-functional wlan0 behind.
SPRDWL_MODULE=$(find "$TMPDIR/lib/modules" -type f -name 'sprdwl_ng.ko*' -print -quit)
test -n "$SPRDWL_MODULE"
command -v modinfo > /dev/null
command -v nm > /dev/null
command -v strings > /dev/null
command -v sha256sum > /dev/null

VERIFY_DIR=$(mktemp -d)
SPRDWL_RAW="$VERIFY_DIR/sprdwl_ng.ko"
case "$SPRDWL_MODULE" in
    *.ko)
        cp "$SPRDWL_MODULE" "$SPRDWL_RAW"
        ;;
    *.ko.xz)
        xz -dc "$SPRDWL_MODULE" > "$SPRDWL_RAW"
        ;;
    *.ko.zst)
        zstd -dc "$SPRDWL_MODULE" > "$SPRDWL_RAW"
        ;;
    *.ko.gz)
        gzip -dc "$SPRDWL_MODULE" > "$SPRDWL_RAW"
        ;;
    *)
        echo "Unsupported sprdwl_ng module compression: $SPRDWL_MODULE" >&2
        exit 1
        ;;
esac

SPRDWL_NAME=$(modinfo -F name "$SPRDWL_RAW")
SPRDWL_VERSION=$(modinfo -F version "$SPRDWL_RAW" || true)
SPRDWL_SRCVERSION=$(modinfo -F srcversion "$SPRDWL_RAW")
SPRDWL_VERMAGIC=$(modinfo -F vermagic "$SPRDWL_RAW")
SPRDWL_DEPENDS=$(modinfo -F depends "$SPRDWL_RAW")
SPRDWL_SHA256=$(sha256sum "$SPRDWL_RAW" | awk '{print $1}')
test "$SPRDWL_NAME" = "sprdwl_ng"
if [ "$SPRDWL_SRCVERSION" != "$UWE5621DS_SRCVERSION" ]; then
    echo "Unexpected sprdwl_ng srcversion: $SPRDWL_SRCVERSION" >&2
    exit 1
fi
case "$SPRDWL_VERMAGIC" in
    "$KERNEL_VERSION "*) ;;
    *)
        echo "Unexpected sprdwl_ng vermagic: $SPRDWL_VERMAGIC" >&2
        exit 1
        ;;
esac
echo "sprdwl_ng module=$SPRDWL_MODULE"
echo "sprdwl_ng srcversion=$SPRDWL_SRCVERSION depends=${SPRDWL_DEPENDS:-none}"
case ",$SPRDWL_DEPENDS," in
    *,uwe5622_bsp_sdio,*)
        echo "sprdwl_ng incorrectly depends on the modular WCN BSP" >&2
        exit 1
        ;;
esac
test -z "$(find "$TMPDIR/lib/modules" -type f -name 'uwe5622_bsp_sdio.ko*' -print -quit)"

nm -a "$SPRDWL_RAW" > "$VERIFY_DIR/sprdwl_ng.nm"
awk 'NF {print $NF}' "$VERIFY_DIR/sprdwl_ng.nm" > "$VERIFY_DIR/sprdwl_ng.symbols"
for symbol in \
    sprdwl_driver_init \
    sprdwl_check_all_ifaces_for_up \
    sprdwl_cfg80211_dump_station \
    sprdwl_cfg80211_get_txpower; do
    grep -Fx "$symbol" "$VERIFY_DIR/sprdwl_ng.symbols"
done
for symbol in unisoc_wlan_init random_mac_set; do
    if grep -Eq "^${symbol}(\.[0-9]+)?$" "$VERIFY_DIR/sprdwl_ng.symbols"; then
        echo "Forbidden UWE5622 symbol found: $symbol" >&2
        exit 1
    fi
done
grep -aF 'unisoc_wifi_mac.txt' "$SPRDWL_RAW" > /dev/null
echo "Verified Rockchip UWE5621DS driver symbols and built-in WCN BSP"

for ini in \
    "$FW/uwe5621ds/wifi_56630001_2ant.ini" \
    "$FW/wifi_56630001_2ant.ini"; do
    printf '%s  %s\n' "$UWE5621DS_2ANT_INI_SHA256" "$ini" | sha256sum --check -
done
for ini in \
    "$FW/uwe5621ds/wifi_56630001_3ant.ini" \
    "$FW/wifi_56630001_3ant.ini"; do
    printf '%s  %s\n' "$UWE5621DS_3ANT_INI_SHA256" "$ini" | sha256sum --check -
done
printf '%s  %s\n' "$UWE5621DS_WCN_SHA256" \
    "$FW/uwe5621ds/wcnmodem_2ant.bin" | sha256sum --check -
strings "$FW/uwe5621ds/wcnmodem_2ant.bin" | \
    grep -Fx 'Platform Version:MARLIN3E_20A_W21.47.4'
strings "$FW/uwe5621ds/wcnmodem_2ant.bin" | \
    grep -Fx 'Project Version:uwe5623_marlin3E_ott'

FINAL_DTB="$TMPDIR/boot/dtb/rockchip/rk3566-torder-tablet.dtb"
test "$(fdtget -t s "$FINAL_DTB" /sprd-wlan compatible)" = "sprd,unisoc-wifi"
test "$(fdtget -t s "$FINAL_DTB" /sprd-wlan status)" = "okay"
test "$(fdtget -t s "$FINAL_DTB" /uwe-bsp compatible)" = "unisoc,uwe_bsp"
test "$(fdtget -t s "$FINAL_DTB" /uwe-bsp status)" = "okay"
test "$(fdtget -t s "$FINAL_DTB" /uwe-bsp unisoc,btwf-file-name)" = \
    "/lib/firmware/uwe5621ds/wcnmodem_2ant.bin"
test "$(fdtget -t s "$FINAL_DTB" /sprd-mtty compatible)" = "sprd,mtty"
test "$(fdtget -t s "$FINAL_DTB" /sprd-mtty status)" = "okay"
for node in \
    /mpp-srv \
    /vdpu@fdea0400 /iommu@fdea0800 \
    /jpegd@fded0000 /iommu@fded0480 \
    /vepu@fdee0000 /iommu@fdee0800 \
    /iep@fdef0000 /iommu@fdef0800 \
    /rkvenc@fdf40000 /iommu@fdf40f00 \
    /rkvdec@fdf80200 /iommu@fdf80800; do
    test "$(fdtget -t s "$FINAL_DTB" "$node" status)" = "okay"
done
for node in /npu@fde40000 /bus-npu /iommu@fde4b000; do
    test "$(fdtget -t s "$FINAL_DTB" "$node" status)" = "okay"
done
test "$(fdtget -t x "$FINAL_DTB" /npu@fde40000 rknpu-supply)" = "6d"
test "$(fdtget -t x "$FINAL_DTB" /bus-npu bus-supply)" = "77"
test "$(fdtget -t x "$FINAL_DTB" /bus-npu pvtm-supply)" = "5"
fdtget -t s "$FINAL_DTB" /chosen bootargs | grep -F "root=UUID=$ROOT_UUID"

{
    printf 'root_filesystem_uuid=%s\n' "$ROOT_UUID"
    printf 'module_name=%s\n' "$SPRDWL_NAME"
    printf 'module_version=%s\n' "${SPRDWL_VERSION:-none}"
    printf 'module_srcversion=%s\n' "$SPRDWL_SRCVERSION"
    printf 'module_vermagic=%s\n' "$SPRDWL_VERMAGIC"
    printf 'module_depends=%s\n' "${SPRDWL_DEPENDS:-none}"
    printf 'module_sha256=%s\n' "$SPRDWL_SHA256"
    printf 'required_symbols=%s\n' \
        'sprdwl_driver_init sprdwl_check_all_ifaces_for_up sprdwl_cfg80211_dump_station sprdwl_cfg80211_get_txpower'
    printf 'forbidden_symbols=absent: unisoc_wlan_init random_mac_set\n'
    printf 'ini_2ant_sha256=%s\n' "$UWE5621DS_2ANT_INI_SHA256"
    printf 'ini_3ant_sha256=%s\n' "$UWE5621DS_3ANT_INI_SHA256"
    printf 'wcnmodem_2ant_sha256=%s\n' "$UWE5621DS_WCN_SHA256"
    printf 'wcn_platform_version=%s\n' 'MARLIN3E_20A_W21.47.4'
    printf 'wcn_project_version=%s\n' 'uwe5623_marlin3E_ott'
    printf 'dtb_sprd_wlan=%s\n' "$(fdtget -t s "$FINAL_DTB" /sprd-wlan compatible)"
    printf 'dtb_uwe_bsp=%s\n' "$(fdtget -t s "$FINAL_DTB" /uwe-bsp compatible)"
    printf 'rockchip_mpp_commit=%s\n' "$MPP_COMMIT"
    printf 'rockchip_mpp_tools=%s\n' 'mpi_enc_test mpi_dec_test mpp_info_test'
    printf 'dtb_mpp_service=%s\n' "$(fdtget -t s "$FINAL_DTB" /mpp-srv status)"
    printf 'dtb_rkvenc=%s\n' "$(fdtget -t s "$FINAL_DTB" /rkvenc@fdf40000 status)"
    printf 'dtb_rkvdec=%s\n' "$(fdtget -t s "$FINAL_DTB" /rkvdec@fdf80200 status)"
    printf 'rknn_toolkit_commit=%s\n' "$RKNN_COMMIT"
    printf 'rknn_runtime=%s\n' '/usr/lib/aarch64-linux-gnu/librknnrt.so'
    printf 'rknn_smoke_model=%s\n' '/usr/share/torder-rknpu/mobilenet_v1.rknn'
    printf 'dtb_rknpu=%s\n' "$(fdtget -t s "$FINAL_DTB" /npu@fde40000 status)"
    printf 'dtb_rknpu_mmu=%s\n' "$(fdtget -t s "$FINAL_DTB" /iommu@fde4b000 status)"
    printf 'chromium_snap_revision=%s\n' '3506'
    printf 'snap_store_revision=%s\n' '1391'
    printf 'audio_route=%s\n' 'RK817 Playback Path=SPK'
    printf 'snap_confine_capabilities=%s\n' "$SNAP_CONFINE_ACTUAL"
    if command -v aarch64-linux-gnu-gcc > /dev/null; then
        printf 'cross_compiler=%s\n' "$(aarch64-linux-gnu-gcc --version | head -n 1)"
    fi
} >> "$DIAGNOSTICS"
grep HandlePowerKey "$TMPDIR/etc/systemd/logind.conf.d/90-powerkey-lock.conf"
cat "$TMPDIR/etc/modules-load.d/touchscreen.conf"
ls "$TMPDIR/usr/local/sbin/powerkey-backlight-toggle.py"
ls "$TMPDIR/etc/systemd/system/powerkey-backlight-toggle.service"
ls "$TMPDIR/etc/systemd/logind.conf.d/90-powerkey-lock.conf"
ls "$TMPDIR/etc/udev/rules.d/99-touch-no-runtime-pm.rules"
grep -F 'KERNEL=="mpp_service", GROUP="render", MODE="0660", TAG+="uaccess"' \
    "$TMPDIR/etc/udev/rules.d/99-rockchip-media.rules"
grep -F 'SUBSYSTEM=="dma_heap", GROUP="render", MODE="0660", TAG+="uaccess"' \
    "$TMPDIR/etc/udev/rules.d/99-rockchip-media.rules"
ls "$TMPDIR/lib/firmware/uwe5621ds/wcnmodem_2ant.bin"
ls "$TMPDIR/lib/firmware/wifi_56630001_3ant.ini"
ls "$TMPDIR/usr/bin/hciattach_opi"
ls "$TMPDIR/usr/bin/torder-tablet-bluetooth"
ls "$TMPDIR/usr/lib/systemd/system/torder-tablet-bluetooth.service"
ls "$TMPDIR/usr/local/sbin/torder-wifi-mac"
ls "$TMPDIR/etc/systemd/system/torder-wifi-mac.service"
ls "$TMPDIR/etc/systemd/system/sysinit.target.wants/torder-wifi-mac.service"
ls "$TMPDIR/usr/bin/mpi_enc_test"
ls "$TMPDIR/usr/bin/mpi_dec_test"
ls "$TMPDIR/usr/bin/mpp_info_test"
ls "$TMPDIR/usr/lib/aarch64-linux-gnu/librockchip_mpp.so"
ls "$TMPDIR/usr/bin/rknn-smoke-test"
ls "$TMPDIR/usr/lib/aarch64-linux-gnu/librknnrt.so"
ls "$TMPDIR/usr/include/rknn_api.h"
ls "$TMPDIR/usr/share/torder-rknpu/mobilenet_v1.rknn"
test "$(readlink "$TMPDIR/usr/lib/aarch64-linux-gnu/librknn_api.so")" = \
    "librknnrt.so"
test -x "$TMPDIR/usr/bin/chromium-browser"
test -x "$TMPDIR/usr/bin/snap"
test -x "$TMPDIR/usr/bin/xdg-settings"
test -x "$TMPDIR/usr/bin/gnome-software"
test -x "$TMPDIR/usr/bin/amixer"
grep -Fq 'Package: gnome-software-plugin-snap' \
    "$TMPDIR/var/lib/dpkg/status"
grep -A1 -Fx 'Package: gnome-software-plugin-snap' \
    "$TMPDIR/var/lib/dpkg/status" | \
    grep -Fx 'Status: install ok installed'
test -x "$TMPDIR/usr/local/sbin/torder-install-bundled-snaps"
test -f "$TMPDIR/etc/systemd/system/torder-install-bundled-snaps.service"
test "$(readlink "$TMPDIR/etc/systemd/system/graphical.target.wants/torder-install-bundled-snaps.service")" = \
    "../torder-install-bundled-snaps.service"
grep -Fq "ExecStart=/usr/bin/amixer -c 0 sset 'Playback Path' SPK" \
    "$TMPDIR/usr/lib/systemd/user/torder-speaker-route.service"
test "$(readlink "$TMPDIR/etc/systemd/user/default.target.wants/torder-speaker-route.service")" = \
    "/usr/lib/systemd/user/torder-speaker-route.service"
for snap_file in \
    bare_5.snap \
    core22_2438.snap \
    core24_1644.snap \
    gtk-common-themes_1535.snap \
    mesa-2404_1836.snap \
    gnome-46-2404_154.snap \
    cups_1237.snap \
    chromium_3506.snap \
    snap-store_1391.snap; do
    test -s "$BUNDLED_SNAP_CACHE/$snap_file"
    test -s "$BUNDLED_SNAP_CACHE/${snap_file%.snap}.assert"
done
grep -Fx 'DefaultDependencies=no' "$TMPDIR/etc/systemd/system/torder-wifi-mac.service"
grep -Fx 'After=local-fs.target' "$TMPDIR/etc/systemd/system/torder-wifi-mac.service"
grep -Fx 'Before=sysinit.target systemd-modules-load.service systemd-udev-trigger.service' \
    "$TMPDIR/etc/systemd/system/torder-wifi-mac.service"
test "$(readlink "$TMPDIR/etc/systemd/system/sysinit.target.wants/torder-wifi-mac.service")" = \
    "../torder-wifi-mac.service"
grep -Fx "wifi-sec.pmf=1" "$TMPDIR/etc/NetworkManager/conf.d/90-torder-wifi.conf"
python3 -m py_compile "$TMPDIR/usr/local/bin/torder-night-light"
ls "$TMPDIR/usr/lib/systemd/user/torder-night-light.service"
test "$(readlink "$TMPDIR/etc/systemd/user/default.target.wants/torder-night-light.service")" = \
    "/usr/lib/systemd/user/torder-night-light.service"
test ! -e "$TMPDIR/lib/firmware/unisoc_wifi_mac.txt"
test -x "$TMPDIR/usr/sbin/dnsmasq"

printf 'result=PASS\n' >> "$DIAGNOSTICS"
chmod 644 "$DIAGNOSTICS"

# Cleanup
cleanup
trap - EXIT

echo "Post-build complete!"
