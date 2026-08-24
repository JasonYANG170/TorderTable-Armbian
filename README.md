# TorderTable-Armbian

Armbian build for Torder Tablet (RK3566) with desktop and optimizations

## Device Info

- **SoC**: Rockchip RK3566 (Cortex-A55 quad-core, up to 1.8GHz)
- **GPU**: Mali-G52 (Panfrost driver)
- **RAM**: 4GB LPDDR4x
- **Display**: 800x1280 DSI panel @90Hz
- **Kernel**: 6.1.115-vendor-rk35xx
- **OS**: Ubuntu Noble 24.04 (Armbian 26.02.0-trunk)
- **DTB**: `rockchip/rk3566-torder-tablet.dtb`

## Features

- **Desktop**: GNOME on Wayland (full desktop)
- **GPU**: Panfrost open-source driver with hardware acceleration
- **Performance**: CPU/GPU locked at max frequency
- **Display**: 90Hz refresh rate (overclocked from 53.39Hz)
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
# The reference module is built on Ubuntu 22.04 with GCC 11.
sudo apt-get update
sudo apt-get install -y gcc-11 g++-11 gcc-11-aarch64-linux-gnu \
  binutils-aarch64-linux-gnu

# Check out the same Armbian revision as the working reference image
git init build
cd build
git remote add origin https://github.com/armbian/build.git
git fetch --depth=1 origin 676832645ddde2e463b689e55fdd7ac81590f1ff
git checkout --detach FETCH_HEAD

# Copy userpatches and the complete working kernel configuration
cp -r /path/to/TorderTable-Armbian/userpatches/* userpatches/
cp /path/to/TorderTable-Armbian/config-6.1.115-vendor-rk35xx \
  config/kernel/linux-rk35xx-vendor.config

# Build desktop image
./compile.sh BOARD=torder-tablet BRANCH=vendor RELEASE=noble \
  KERNELBRANCH=commit:41da3e69e16b9de57eca897215e8b0adc6efdc8b \
  BUILD_DESKTOP=yes DESKTOP_ENVIRONMENT=gnome \
  DESKTOP_ENVIRONMENT_CONFIG_NAME=config_base KERNEL_CONFIGURE=no \
  PREFER_DOCKER=no
```

## Fixes Applied

### 1. Filesystem UUID Boot Fix
- **Problem**: PARTLABEL discovery can fail in initramfs after first-boot resize
- **Fix**: Writes the root filesystem UUID to both `armbianEnv.txt` and DTB bootargs

### 2. UWE5621DS WiFi and Bluetooth
- **Problem**: Armbian's generated generic UWE5622 branch enabled `OTT_UWE` and scan random-MAC support. NetworkManager then sent `WIFI_CMD_RND_MAC`; `wlan0` existed, but scans returned no APs and hotspot creation failed.
- **Fix**: Replaces `unisocwifi` with the Rockchip Linux 6.1 UWE5621DS implementation from source commit `4c63dfb`. It enables `UWE5621_FTR`, uses device-tree platform registration, and disables `OTT_UWE`, random scan MAC, IBSS, NAN, and RTT. The working built-in WCN BSP and Bluetooth paths are left intact.
- **MAC**: Generates a stable address from each device before module probing. The driver reads it with bounded parsing and falls back safely without shipping a captured factory MAC.
- **Calibration**: Stores the known-good 2-antenna and 3-antenna INI files byte-for-byte with CRLF endings protected by `.gitattributes`.
- **CI check**: Builds on Ubuntu 22.04/GCC 11 and rejects a module with `unisoc_wlan_init`, `random_mac_set`, a modular WCN BSP dependency, wrong symbols, firmware hashes, calibration hashes, vermagic, or DTB properties. `uwe5621ds-diagnostics.txt` is included with every successful image.
- **Files**: `0001-uwe5621ds-rockchip-driver.patch`, `0002-uwe5621ds-load-device-mac.patch`, `torder-wifi-mac.service`, `90-torder-wifi.conf`, and UWE5621DS firmware assets

### 3. GPU Panfrost Fix
- **Problem**: Panfrost GPU page fault causing software rendering fallback
- **Fix**: X11 configuration with DRI2, disabled PageFlip
- **Files**: `/etc/X11/xorg.conf.d/20-panfrost.conf`

### 4. Performance Optimization
- **Problem**: System laggy with default ondemand governor
- **Fix**: CPU locked at1800MHz, GPU at800MHz (performance mode)
- **Files**: `max-performance.service`

### 5. Display Refresh Rate
- **Problem**: Factory timing runs at only 53.39Hz
- **Fix**: Pixel clock set from 60MHz to 101.14776MHz (90Hz)
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

### 8. GNOME Night Light
- **Problem**: GNOME reported Night Light as active on X11 without changing the panel color
- **Fix**: A user service mirrors the GNOME target color temperature to the DSI output through RandR
  - Writes the gamma LUT only when Night Light or its target temperature changes
  - Avoids repeated LUT updates and visible display flicker
- **Files**: `/usr/local/bin/torder-night-light`, `torder-night-light.service`

## Architecture

```
assets/uwe5621ds/
|-- torder-wifi-mac              # Per-device MAC provisioning
|-- torder-wifi-mac.service      # Runs before module and udev probing
`-- 90-torder-wifi.conf          # UWE5621DS hotspot compatibility
assets/display/
|-- torder-night-light.py        # X11 Night Light RandR fallback
`-- torder-night-light.service   # GNOME user-session service
scripts/
`-- post-build.sh                # Installs and verifies device fixes
userpatches/
|-- config/boards/
|   `-- torder-tablet.csc         # Board config and image packages
|-- customize/images/
|   `-- torder-tablet-gpu-perf-fix.sh
|-- kernel/rk35xx-vendor-6.1/
|   |-- 0001-uwe5621ds-rockchip-driver.patch # Rockchip 6.1 driver branch
|   `-- 0002-uwe5621ds-load-device-mac.patch  # Safe per-device WiFi MAC load
`-- patch/kernel/rk35xx-vendor-6.1/dt/
    `-- rk3566-torder-tablet.dts        # Generic device tree
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
| Pixel Clock | 101.14776 MHz |
| DSI Bandwidth | 607 Mbps/lane |
| Refresh Rate | **90 Hz** |
| DSI Lanes | 4 |

## Performance

| Component | Frequency | Governor |
|-----------|-----------|----------|
| CPU (A55 x4) | 1800 MHz | performance |
| GPU (Mali-G52) | 800 MHz | performance |

## Known Limitations

- The UWE5621DS firmware does not support WPA3-SAE. WPA3-only access points
  must enable WPA2/WPA3 transition mode with WPA2-PSK clients permitted.
- No camera hardware detected
- The 90Hz panel timing is an overclock over the factory 53.39Hz mode
