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
    Option "DRI" "2"
    Option "AccelMethod" "glamor"
    Option "PageFlip" "off"
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

    # Enable animations (smooth UI experience)
    gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true
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
# Fix 7: Power button lock screen & backlight control
# ============================================================
# Power button: lock screen + turn off backlight
# Press again: restore backlight (wake)
cat > "${SDCARD}/usr/local/bin/lockscreen-monitor.sh" << 'PWREOF'
#!/bin/bash
BACKLIGHT="/sys/class/backlight/backlight/brightness"
MAX_BRIGHT=$(cat /sys/class/backlight/backlight/max_brightness)

# Wait for evtest to be available
sleep 5

# Check if evtest is available
if ! command -v evtest &>/dev/null; then
    apt-get install -y evtest &>/dev/null
fi

# Grab power key device exclusively
POWER_DEV=""
for dev in /dev/input/event*; do
    if evtest --query "$dev" EV_KEY KEY_POWER 2>/dev/null; then
        POWER_DEV="$dev"
        break
    fi
done

if [ -z "$POWER_DEV" ]; then
    echo "Power key device not found"
    exit 1
fi

echo "Monitoring power key: $POWER_DEV"

evtest --grab "$POWER_DEV" | while read line; do
    if echo "$line" | grep -q "code 116 (KEY_POWER), value 1"; then
        BL=$(cat "$BACKLIGHT" 2>/dev/null)
        if [ "$BL" -eq 0 ]; then
            echo "$MAX_BRIGHT" > "$BACKLIGHT"
        else
            SESSION_ID=$(loginctl list-sessions --no-legend | grep armbian | awk '{print $1}')
            if [ -n "$SESSION_ID" ]; then
                loginctl lock-session "$SESSION_ID"
            fi
            sleep 0.3
            echo 0 > "$BACKLIGHT"
        fi
    fi
done
PWREOF
chmod 755 "${SDCARD}/usr/local/bin/lockscreen-monitor.sh"

cat > "${SDCARD}/etc/systemd/system/lockscreen-monitor.service" << 'SVCEOF'
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

chroot "${SDCARD}" /bin/bash -c "systemctl enable lockscreen-monitor.service 2>/dev/null" || true

# Install evtest
chroot "${SDCARD}" /bin/bash -c "apt-get install -y evtest 2>/dev/null" || true

display_alert "Torder Tablet" "Power button lock screen & backlight control configured" "info"

display_alert "Torder Tablet" "GPU & performance optimizations applied" "info"
