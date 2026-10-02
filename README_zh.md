[简体中文](README_zh.md) | [English](README.md)

# TorderTable-Armbian

Torder 平板（RK3566）的 Armbian 构建，包含桌面环境与设备优化

## 设备信息

- **SoC**：Rockchip RK3566（Cortex-A55 四核，高达 1.8GHz）
- **GPU**：Mali-G52（Panfrost 驱动程序）
- **RAM**：4GB LPDDR4x
- **显示**：800x1280 DSI 面板 @90Hz
- **内核**：6.1.115-vendor-rk35xx
- **操作系统**：Ubuntu Noble 24.04（Armbian 26.02.0-trunk）
- **DTB**：`rockchip/rk3566-torder-tablet.dtb`

## 功能

- **桌面**：Wayland 上的 GNOME（完整桌面）
- **GPU**：具有硬件加速功能的 Panfrost 开源驱动程序
- **视频编解码器**：Rockchip MPP H.264/H.265 硬件编码和解码
- **NPU**：带有 RKNN Runtime 2.3.2 和模型冒烟测试的 RK3566 RKNPU
- **浏览器**：捆绑 ARM64 Chromium Snap，具有离线首次启动安装功能
- **应用程序商店**：支持 Snap 的 GNOME 软件和 Snap Store 桌面应用程序
- **音频**：桌面音频服务器启动后RK817内部扬声器路由恢复
- **性能**：CPU/GPU 锁定在最大频率
- **显示**：90Hz 刷新率（从 53.39Hz 超频）
- **优化**：禁用Tracker、动画、繁重服务
- **无线**：UWE5621DS 2.4/5GHz WiFi、蓝牙和 WPA2 热点支持
- **电源键**：锁定屏幕、背光关闭和触摸安全唤醒

## 构建

### GitHub Actions（推荐）

1. 推送到此存储库
2. 转到Actions 选项卡
3. 运行“Build Armbian”工作流程
4. 完成后下载构建产物

### 本地构建

```bash
# The reference module is built on Ubuntu 22.04 with GCC 11.
sudo apt-get update
sudo apt-get install -y gcc-11 g++-11 gcc-11-aarch64-linux-gnu \
  g++-11-aarch64-linux-gnu binutils-aarch64-linux-gnu cmake ninja-build

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

## 已应用的修复

### 1. 文件系统 UUID 引导修复
- **问题**：首次启动调整大小后，initramfs 中的 PARTLABEL 发现可能会失败
- **修复**：将根文件系统 UUID 写入 `armbianEnv.txt` 和 DTB bootargs

### 2.UWE5621DS WiFi 和蓝牙
- **问题**：Armbian 生成的通用 UWE5622 分支启用了 `OTT_UWE` 并扫描随机 MAC 支持。 NetworkManager随后发送`WIFI_CMD_RND_MAC`； `wlan0` 存在，但扫描未返回 AP，并且热点创建失败。
- **修复**：将 `unisocwifi` 替换为来自源提交 `4c63dfb` 的 Rockchip Linux 6.1 UWE5621DS 实现。它启用 `UWE5621_FTR`，使用基于设备树的平台设备注册，并禁用 `OTT_UWE`、随机扫描 MAC、IBSS、NAN 和 RTT。工作的内置 WCN BSP 和蓝牙路径保持不变。
- **MAC**：在驱动模块探测之前，为每台设备生成稳定的 MAC 地址。驱动通过带边界检查的解析读取地址，并在失败时安全回退，镜像中不包含采集到的出厂 MAC。
- **校准**：逐字节存储已知良好的 2 天线和 3 天线 INI 文件，并以 CRLF 结尾受 `.gitattributes` 保护。
- **CI 检查**：使用 Ubuntu 22.04/GCC 11 构建；若模块含 `unisoc_wlan_init`、`random_mac_set`、模块化 WCN BSP 依赖，或符号、固件哈希、校准文件哈希、vermagic、DTB 属性不正确，则拒绝构建结果。每个成功镜像均包含 `uwe5621ds-diagnostics.txt`。
- **文件**：`0001-uwe5621ds-rockchip-driver.patch`、`0002-uwe5621ds-load-device-mac.patch`、`torder-wifi-mac.service`、`90-torder-wifi.conf` 和 UWE5621DS 固件资产

### 3. GPU Panfrost 修复
- **问题**：Panfrost GPU 页面错误导致软件渲染回退
- **修复**：使用 DRI2 的 X11 配置，禁用 PageFlip
- **文件**：`/etc/X11/xorg.conf.d/20-panfrost.conf`

### 4.硬件视频编解码器
- **问题**：内核包含 Rockchip MPP 驱动程序，但板 DTB 中每个编解码器和 IOMMU 节点均被禁用，因此 `/dev/mpp_service` 不存在。
- **修复**：启用 RKVENC、RKVDEC、VDPU、VEPU、JPEG、IEP 及其 IOMMU。 CI 构建固定的 Rockchip MPP 用户空间库和测试工具，而 udev 授予桌面 `render` 组对 MPP、RGA 和 DMA 堆的访问权限。
- **验证**：H.264 和 H.265 硬件编码/解码往返以非特权桌面用户身份通过​​。

### 5.RKNPU加速
- **问题**：RKNPU 驱动程序内置于内核中，但 NPU、NPU 总线和 IOMMU 在板 DTB 中被禁用，并且 RKNN 用户空间运行时不存在。
- **修复**：按熔丝配置允许的最高 900MHz 启用 RK3566 RKNPU，通过主板共享稳压器为 NPU 与总线供电，并从官方 `airockchip/rknn-toolkit2` 仓库安装固定版本的 RKNN Runtime 2.3.2 文件。
- **验证**：随附的 `rknn-smoke-test` 以非特权桌面用户身份运行真实的 RK3566 MobileNet 模型。

### 6. 性能优化
- **问题**：默认 ondemand 调频策略导致系统卡顿
- **修复**：CPU锁定在1800MHz，GPU锁定在800MHz（性能模式）
- **文件**：`max-performance.service`

### 7. 显示刷新率
- **问题**：出厂时序仅以 53.39Hz 运行
- **修复**：像素时钟设置从 60MHz 到 101.14776MHz (90Hz)
- **文件**：设备树 `rk3566-torder-tablet.dts`

### 8.GNOME 优化
- **问题**：GNOME 对于 RK3566 来说太重
- **修复**：
  - 禁用Tracker文件索引
  - 禁用动画
  - 禁用CUPS，无人值守升级
  - ZRAM 交换（1GB LZ4）
- **文件**：`99-torder-optimize.sh`、`zram-swap.service`

### 9. 电源键锁+背光
- **问题**：电源键无法可靠地锁定/唤醒平板电脑桌面
- **修复**：安装 `powerkey-backlight-toggle.service`
  - 服务读取RK805电源键输入设备，无需独占控制
  - 服务随 graphical target 启动，并在 `systemd-logind` 之后运行
  - 电源键锁定用户会话并将背光调暗至 `0`
  - 第二次按下可恢复之前的亮度

### 10. Chromium、应用程序商店和 Snap 限制
- **问题**：Firefox 和 Chromium 在启动前失败，因为最终镜像丢失了 `snap-confine` 所需的文件 capabilities； Chromium 的 Ubuntu 软件包也不包含 Snap 有效负载。
- **修复**：镜像处理后重新设置并验证 Noble `snap-confine` 所需的完整 capabilities 集。镜像预置固定版本的 ARM64 Chromium 151、Snap Store 及所需的基础/内容 Snap 包，在首次启动桌面前离线安装。GNOME Software 及其 Snap 插件以原生软件包安装。
- **验证**：CI 检查浏览器启动器、两种应用商店、离线 Snap 安装文件、安装顺序，以及最终 ext4 文件系统中的 capabilities 元数据。

### 11.RK817内置扬声器
- **问题**：检测到编解码器并且 PulseAudio 正在运行，但通用混音器恢复选定的 `Playback Path=HP`，使内部扬声器保持静音。
- **修复**：每用户服务在桌面音频服务器之后运行，并选择 `Playback Path=SPK` 并启用扬声器输出。 RK817 DAPM 继续控制流之间的底层功放切换。
- **验证**：使用 ALSA `Front_Center.wav` 示例在设备上验证了通过默认 PulseAudio 输出设备的播放。
  - 保留 `bl_power=0` 并避免合成输入，以便触摸控制器保持响应
- **文件**：`/usr/local/sbin/powerkey-backlight-toggle.py`、`powerkey-backlight-toggle.service`

### 8.GNOME 夜灯
- **问题**：GNOME 报告夜灯在 X11 上处于活动状态，而不更改面板颜色
- **修复**：用户服务通过 RandR 将 GNOME 目标色温镜像到 DSI 输出
  - 仅当夜灯或其目标温度发生变化时写入伽玛 LUT
  - 避免重复的 LUT 更新和可见的显示闪烁
- **文件**：`/usr/local/bin/torder-night-light`、`torder-night-light.service`

## 项目结构

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

## 提取的设备文件

工作设备的参考文件：

- `armbian-release` - Armbian 发布信息
- `config-6.1.115-vendor-rk35xx` - 内核配置
- `boot/` - 启动文件（armbianEnv.txt、boot.cmd、boot.scr）
- `dtb/rockchip/rk3566-torder-tablet.dtb` - 编译的DTB
- `kernel-packages.txt` - 内核包
- `armbian-packages.txt` - Armbian 软件包
- `installed-packages.txt` - 完整软件包列表
- `kernel-modules.txt` - 内核模块
- `partition-info.txt` - 分区布局

## 显示时序

|参数|数值|
|-----------|-------|
|分辨率| 800x1280 |
|像素时钟| 101.14776兆赫|
| DSI 带宽 | 607 Mbps/通道 |
|刷新率| **90 赫兹** |
| DSI 通道 | 4 |

## 性能

|组件|频率|调频策略|
|-----------|-----------|----------|
| CPU (A55 x4) | 1800兆赫|性能 |
| GPU (Mali-G52) | 800兆赫|性能 |

## 已知限制

- UWE5621DS 固件不支持 WPA3-SAE。仅 WPA3 接入点
  必须启用 WPA2/WPA3 转换模式并允许 WPA2-PSK 客户端。
- 未检测到相机硬件
- 90Hz 面板时序是对工厂 53.39Hz 模式的超频
