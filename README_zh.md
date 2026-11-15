[简体中文](README_zh.md) | [English](README.md)

# TorderTable-Armbian

Torder 平板的 Armbian 桌面版和控制台版镜像。

## 设备信息

- **SoC**: Rockchip RK3566 (Cortex-A55 四核，1.8 GHz)
- **GPU**: Mali-G52 (Panfrost)
- **RAM**: 4 GB LPDDR3
- **屏幕**: 800 × 1280 DSI, 60 Hz
- **内核**: `6.1.115-vendor-rk35xx`
- **系统**: Ubuntu Noble 24.04
- **引导**：U-Boot v2026.10
- **摄像头**：前置 GC02M1，后置 GC02M0
- **DTB**: `rockchip/rk3566-torder-tablet.dtb`

## 构建

### GitHub Actions

推送到 `main`，或在 Actions 页面运行 **Build Armbian**。从 [Releases](https://github.com/JasonYANG170/TorderTable-Armbian/releases) 下载桌面版或控制台版镜像。

### 本地构建

使用 Ubuntu 22.04 和 GCC 11。以下命令构建 GNOME 基础镜像，正式发布的镜像还按 [CI 工作流](.github/workflows/build.yml) 安装 Rockchip MPP、RKNN 和设备适配组件。

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
