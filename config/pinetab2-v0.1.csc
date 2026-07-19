# Pine64 PineTab2 v0.1 - RK3566 Tablet
BOARD_NAME="PineTab2 v0.1"
BOARD_VENDOR="pine64"
BOOT_SOC="rk3566"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
INTRODUCED="2024"
BOOTCONFIG="generic-rk3568_defconfig"
KERNEL_TARGET="vendor"
FULL_DESKTOP="no"
BOOT_FDT_FILE="rockchip/rk3566-pinetab2-v0.1.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BUILD_MINIMAL="yes"

# Override kernel source to use local linux directory
function post_family_config__pinetab2_custom_kernel_source() {
	display_alert "$BOARD" "Using local kernel source: /home/yang/桌面/rkdev/linux" "info"
	KERNELSOURCE="/home/yang/桌面/rkdev/linux"
	KERNELBRANCH="branch:device/pine64-pinetab2_stable"
	# Local kernel is 6.5.0
	declare -g KERNEL_MAJOR_MINOR="6.5"
}

# Mainline U-Boot
function post_family_config__pinetab2_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2025.10"
	declare -g BOOTPATCHDIR="v2025.10"

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
