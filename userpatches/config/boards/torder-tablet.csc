# Torder Tablet - RK3566 Tablet
BOARD_NAME="Torder Tablet"
BOARD_VENDOR="torder"
BOOT_SOC="rk3566"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
INTRODUCED="2025"
BOOTCONFIG="generic-rk3568_defconfig"
KERNEL_TARGET="vendor"
BOOT_FDT_FILE="rockchip/rk3566-torder-tablet.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
GOVERNOR="performance"
PACKAGE_LIST_BOARD="dnsmasq-base"

# Mainline U-Boot
function post_family_config__torder_tablet_use_mainline_uboot() {
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
