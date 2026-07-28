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
# Fix 7: Night Light via xsct (Xwayland gamma workaround)
# ============================================================
# RK3566 DRM driver lacks gamma LUT support, so GNOME Night Light
# and redshift/gammastep cannot work. Use xsct via Xwayland instead.
apt_install_packages "xsct" "xsct" || true
display_alert "Torder Tablet" "Installed xsct for Night Light support" "info"

# Create Night Light first-login script
NL_LOGIN="${SDCARD}/etc/armbian_first_login.d/95-torder-nightlight.sh"
cat > "${NL_LOGIN}" << 'NLSCRIPT'
#!/bin/bash
# Torder Night Light setup via xsct (Xwayland)
# Must run after GNOME session starts
if [ "$(id -u)" -eq 1000 ]; then
    mkdir -p ~/.local/bin ~/.config/systemd/user

    # Create nightlight script
    cat > ~/.local/bin/nightlight.sh << 'NLEOF'
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=$(ls /run/user/1000/.mutter-Xwaylandauth.* 2>/dev/null | head -1)
sleep 5
xsct 3500
NLEOF
    chmod +x ~/.local/bin/nightlight.sh

    # Create systemd service
    cat > ~/.config/systemd/user/nightlight.service << 'SVCEOF'
[Unit]
Description=Night Light (Xwayland)
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/home/armbian/.local/bin/nightlight.sh
RemainAfterExit=yes

[Install]
WantedBy=default.target
SVCEOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable nightlight.service 2>/dev/null || true
fi
NLSCRIPT
chmod +x "${NL_LOGIN}"
display_alert "Torder Tablet" "Created Night Light first-login setup" "info"

display_alert "Torder Tablet" "GPU & performance optimizations applied" "info"
