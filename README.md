# TorderTable-Armbian

Armbian build for Pine64 PineTab2 v0.1 (headless/embedded configuration)

## Features

- Based on Armbian with RK35XX vendor kernel (6.1)
- Minimal CLI system (Ubuntu Noble 24.04)
- Headless configuration: display, WiFi, camera, touch, amplifier disabled

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
./compile.sh BOARD=pinetab2-v0.1 BRANCH=vendor RELEASE=noble BUILD_DESKTOP=no BUILD_MINIMAL=yes KERNEL_CONFIGURE=no
```

## Device Tree Modifications

The following peripherals are disabled in the device tree:

- **Display**: LCD, DSI, HDMI, backlight, VOP
- **WiFi**: SDIO interface (sdmmc1)
- **Camera**: OV5648 sensor, CSI DPHY
- **Touchscreen**: Goodix GT911
- **Amplifier**: Speaker amplifier, I2S audio

## Files

- `userpatches/config/boards/pinetab2-v0.1.csc` - Board configuration
- `userpatches/patch/kernel/rk35xx-vendor-6.1/dt/` - Device tree files
