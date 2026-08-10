# TorderTable-Armbian

Armbian build for Torder Tablet (RK3566) with desktop and optimizations

## Device Info

- **SoC**: Rockchip RK3566 (Cortex-A55 quad-core, up to 1.8GHz)
- **GPU**: Mali-G52 (Panfrost driver)
- **RAM**: 4GB LPDDR4x
- **Display**: 800x1280 DSI panel @100Hz
- **Kernel**: 6.1.115-vendor-rk35xx
- **OS**: Ubuntu Noble 24.04 (Armbian 26.02.0-trunk)
- **DTB**: `rockchip/rk3566-torder-tablet.dtb`

## Features

- **Desktop**: GNOME on Wayland (full desktop)
- **GPU**: Panfrost open-source driver with hardware acceleration
- **Performance**: CPU/GPU locked at max frequency
- **Display**: 100Hz refresh rate (overclocked from53Hz)
- **Optimized**: Disabled Tracker, animations, heavy services
- **Wireless**: UWE5621DS 2.4/5GHz WiFi, Bluetooth, and WPA2 hotspot support
- **Power key**: Lock screen, backlight off, and touch-safe wake

## Build

### GitHub Actions (Recommended)

1. Push to this repository
2. Go to Actions tab
3. Run "Build Armbian" workflow
4. Download the artifact when complete

### Local Build

```bash
# Clone Armbian build system
git clone --depth=1 https://github.com/armbian/build.git
cd build

# Copy userpatches
cp -r /path/to/TorderTable-Armbian/userpatches/* userpatches/

# Build desktop image
./compile.sh BOARD=torder-tablet BRANCH=vendor RELEASE=noble BUILD_DESKTOP=yes KERNEL_CONFIGURE=no
```

## Fixes Applied

### 1. Filesystem UUID Boot Fix
- **Problem**: PARTLABEL discovery can fail in initramfs after first-boot resize
- **Fix**: Writes the root filesystem UUID to both `armbianEnv.txt` and DTB bootargs

### 2. UWE5621DS WiFi and Bluetooth
- **Problem**: WiFi cannot scan with an invalid MAC, and optional PMF prevents AP startup
- **Fix**: Generates a stable per-device MAC before driver probing and disables PMF for WPA2 hotspots
- **Files**: `torder-wifi-mac.service`, `90-torder-wifi.conf`, UWE5621DS firmware assets

### 3. GPU Panfrost Fix
- **Problem**: Panfrost GPU page fault causing software rendering fallback
- **Fix**: X11 configuration with DRI2, disabled PageFlip
- **Files**: `/etc/X11/xorg.conf.d/20-panfrost.conf`

### 4. Performance Optimization
- **Problem**: System laggy with default ondemand governor
- **Fix**: CPU locked at1800MHz, GPU at800MHz (performance mode)
- **Files**: `max-performance.service`

### 5. Display Refresh Rate
- **Problem**: Panel runs at53Hz instead of60Hz
- **Fix**: Pixel clock overclocked from60MHz to112.39MHz (100Hz)
- **Files**: Device tree `rk3566-torder-tablet.dts`

### 6. GNOME Optimization
- **Problem**: GNOME too heavy for RK3566
- **Fix**: 
  - Disabled Tracker file indexing
  - Disabled animations
  - Disabled CUPS, unattended-upgrades
  - ZRAM swap (1GB LZ4)
- **Files**: `99-torder-optimize.sh`, `zram-swap.service`

### 7. Power Key Lock + Backlight
- **Problem**: Power key did not reliably lock/wake the tablet desktop
- **Fix**: Installs `powerkey-backlight-toggle.service`
  - Service reads the RK805 power-key input device without taking exclusive control
  - Service starts with the graphical target, after `systemd-logind`
  - Power key locks the user session and dims backlight to `0`
  - Second press restores the previous brightness
  - Keeps `bl_power=0` and avoids synthetic input so the touch controller remains responsive
- **Files**: `/usr/local/sbin/powerkey-backlight-toggle.py`, `powerkey-backlight-toggle.service`

## Architecture

```
assets/uwe5621ds/
|-- torder-wifi-mac              # Per-device MAC provisioning
|-- torder-wifi-mac.service      # Runs before module and udev probing
`-- 90-torder-wifi.conf          # UWE5621DS hotspot compatibility
scripts/
`-- post-build.sh                # Installs and verifies device fixes
userpatches/
|-- config/boards/
|   `-- torder-tablet.csc         # Board config and image packages
|-- customize/images/
|   `-- torder-tablet-gpu-perf-fix.sh
`-- patch/kernel/rk35xx-vendor-6.1/dt/
    `-- rk3566-torder-tablet.dts  # Generic device tree
```

## Extracted Device Files

Reference files from working device:

- `armbian-release` - Armbian release info
- `config-6.1.115-vendor-rk35xx` - Kernel configuration
- `boot/` - Boot files (armbianEnv.txt, boot.cmd, boot.scr)
- `dtb/rockchip/rk3566-torder-tablet.dtb` - Compiled DTB
- `kernel-packages.txt` - Kernel packages
- `armbian-packages.txt` - Armbian packages
- `installed-packages.txt` - Full package list
- `kernel-modules.txt` - Kernel modules
- `partition-info.txt` - Partition layout

## Display Timing

| Parameter | Value |
|-----------|-------|
| Resolution | 800x1280 |
| Pixel Clock | 112.39 MHz |
| DSI Bandwidth | 756 Mbps/lane |
| Refresh Rate | **100 Hz** |
| DSI Lanes | 4 |

## Performance

| Component | Frequency | Governor |
|-----------|-----------|----------|
| CPU (A55 x4) | 1800 MHz | performance |
| GPU (Mali-G52) | 800 MHz | performance |

## Known Limitations

- Night Light does not work on Wayland (Mutter limitation)
- No camera hardware detected
- DSI panel cannot be overclocked beyond ~120Hz (hardware limit)
