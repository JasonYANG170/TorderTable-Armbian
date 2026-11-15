[简体中文](README_zh.md) | [English](README.md)

# TorderTable-Armbian

Armbian desktop and console images for the Torder tablet.

## Device Info

- **SoC**: Rockchip RK3566 (Cortex-A55, 4 cores, 1.8 GHz)
- **GPU**: Mali-G52 (Panfrost)
- **RAM**: 4 GB LPDDR4x
- **Display**: 800 × 1280 DSI, 60 Hz
- **Kernel**: `6.1.115-vendor-rk35xx`
- **OS**: Ubuntu Noble 24.04
- **DTB**: `rockchip/rk3566-torder-tablet.dtb`

## Build

### GitHub Actions

Push to `main` or run **Build Armbian** in Actions. Get the desktop or console image from [Releases](https://github.com/JasonYANG170/TorderTable-Armbian/releases).

### Local Build

Use Ubuntu 22.04 with GCC 11. The commands build the GNOME base image. The [workflow](.github/workflows/build.yml) also prepares Rockchip MPP and RKNN and runs the device post-build script for release images.

```bash
sudo apt-get update
sudo apt-get install -y git gcc-11 g++-11 gcc-11-aarch64-linux-gnu \
  g++-11-aarch64-linux-gnu binutils-aarch64-linux-gnu cmake ninja-build

git init build
git -C build remote add origin https://github.com/armbian/build.git
git -C build fetch --depth=1 origin 676832645ddde2e463b689e55fdd7ac81590f1ff
git -C build checkout --detach FETCH_HEAD
cp -a userpatches/. build/userpatches/
cp config-6.1.115-vendor-rk35xx build/config/kernel/linux-rk35xx-vendor.config

cd build
./compile.sh BOARD=torder-tablet BRANCH=vendor RELEASE=noble \
  KERNELBRANCH=commit:41da3e69e16b9de57eca897215e8b0adc6efdc8b \
  BUILD_DESKTOP=yes DESKTOP_ENVIRONMENT=gnome \
  DESKTOP_ENVIRONMENT_CONFIG_NAME=config_base KERNEL_CONFIGURE=no PREFER_DOCKER=no
```
