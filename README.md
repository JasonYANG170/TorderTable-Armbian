# TorderTable-Armbian

Armbian build for Torder Tablet (RK3566)

## Device Info

- **SoC**: Rockchip RK3566 (Cortex-A55 quad-core, up to 1.8GHz)
- **Kernel**: 6.1.115-vendor-rk35xx
- **OS**: Ubuntu Noble 24.04 (Armbian 26.02.0-trunk)
- **DTB**: `rockchip/rk3566-torder-tablet.dtb`

## Features

- Based on Armbian with RK35XX vendor kernel (6.1)
- Minimal CLI system (Ubuntu Noble 24.04)
- GPT partition table with SPL blobs boot scenario

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

# Build
./compile.sh BOARD=torder-tablet BRANCH=vendor RELEASE=noble BUILD_DESKTOP=no BUILD_MINIMAL=yes KERNEL_CONFIGURE=no
```

## Extracted Device Files

The following files were extracted from a working device for reference:

- `armbian-release` - Armbian release info from the device
- `config-6.1.115-vendor-rk35xx` - Kernel configuration
- `boot/` - Boot files (armbianEnv.txt, boot.cmd, boot.scr, boot.bmp)
- `dtb/rockchip/rk3566-torder-tablet.dtb` - Compiled device tree blob
- `dtb/rockchip/overlay/` - DTB overlays
- `kernel-packages.txt` - Installed kernel packages
- `armbian-packages.txt` - Installed Armbian packages
- `installed-packages.txt` - Full package list
- `kernel-modules.txt` - Kernel module list
- `dtb-files-found.txt` - DTB files found on device
- `partition-info.txt` - Partition layout info

## Board Configuration

- `userpatches/config/boards/torder-tablet.csc` - Board configuration for Torder Tablet
- `userpatches/patch/kernel/rk35xx-vendor-6.1/dt/rk3566-torder-tablet.dts` - Device tree source

## Files

- `userpatches/config/boards/torder-tablet.csc` - Board configuration
- `userpatches/patch/kernel/rk35xx-vendor-6.1/dt/` - Device tree source files
