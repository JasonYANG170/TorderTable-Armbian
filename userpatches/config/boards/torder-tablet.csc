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

# Fix PARTLABEL issue: set GPT partition name to "rootfs"
# Without this, reboot hangs in initramfs because U-Boot uses root=PARTLABEL=rootfs
# but GPT partition has no name set
function post_image__torder_tablet_set_partition_name() {
	display_alert "$BOARD" "Setting GPT partition name to rootfs for PARTLABEL boot" "info"

	# Find the image file - try common Armbian output paths
	local image_file=""
	for candidate in \
		"${DESTIMG}/${IMAGE_PATH}" \
		"${DESTIMG}/images/${IMAGE_PATH}" \
		"${DESTIMG}/images/"*.img; do
		if [[ -f "${candidate}" ]]; then
			image_file="${candidate}"
			break
		fi
	done

	if [[ -n "${image_file}" && -f "${image_file}" ]]; then
		display_alert "$BOARD" "Setting partition name on: ${image_file}" "info"

		# Method 1: Try sfdisk (most reliable for setting partition name)
		if command -v sfdisk &>/dev/null; then
			# Get the partition start offset
			local part_info
			part_info=$(sfdisk -d "${image_file}" 2>/dev/null | grep "mmcblk0p1\|start=" | head -1)
			if [[ -n "${part_info}" ]]; then
				echo "${part_info}" | sfdisk --append --part-name rootfs "${image_file}" 2>/dev/null || true
			fi
			# Alternative: directly set name on existing partition
			sfdisk --part-name 1 rootfs "${image_file}" 2>/dev/null || true
		fi

		# Method 2: Try sgdisk (gdisk)
		if command -v sgdisk &>/dev/null; then
			sgdisk -c 1:rootfs "${image_file}" 2>/dev/null || true
		fi

		# Method 3: Try using parted on loop device (fallback)
		if command -v losetup &>/dev/null && command -v parted &>/dev/null; then
			local loop_dev
			loop_dev=$(losetup --find --show --partscan "${image_file}" 2>/dev/null)
			if [[ -n "${loop_dev}" ]]; then
				# Wait for partition device to appear
				sleep 1
				if [[ -b "${loop_dev}p1" ]]; then
					parted "${loop_dev}" name 1 rootfs 2>/dev/null || true
				fi
				losetup -d "${loop_dev}" 2>/dev/null || true
			fi
		fi

		display_alert "$BOARD" "GPT partition name set to rootfs" "info"
	else
		display_alert "$BOARD" "Warning: Could not find image file to set partition name" "warn"
	fi
}

# Patch initramfs to support PARTLABEL=rootfs in boot scripts
function post_install__torder_tablet_initramfs_partlabel_fix() {
	display_alert "$BOARD" "Patching initramfs to support PARTLABEL" "info"

	# Patch scripts/local to recognize PARTLABEL in root= parameter
	local local_script="${SDCARD}/usr/share/initramfs-tools/scripts/local"
	if [[ -f "${local_script}" ]]; then
		if ! grep -q "PARTLABEL" "${local_script}"; then
			sed -i 's|UUID=\*\|LABEL=\*\|PARTUUID=\*\|/dev/\*|UUID=*|LABEL=*|PARTUUID=*|PARTLABEL=*|/dev/*|g' "${local_script}" 2>/dev/null || true
			display_alert "$BOARD" "initramfs scripts/local patched for PARTLABEL support" "info"
			else
				display_alert "$BOARD" "initramfs scripts/local already has PARTLABEL support" "info"
			fi
	fi

	# Also ensure /dev/disk/by-partlabel directory exists
	mkdir -p "${SDCARD}/dev/disk/by-partlabel" 2>/dev/null || true
}

# ============================================================
# Ensure DTB is installed to boot partition
# The DTS patch may not compile correctly during kernel build,
# so we copy the pre-compiled DTB directly to the boot partition.
# ============================================================
function post_install__torder_tablet_install_dtb() {
	display_alert "$BOARD" "Installing DTB to boot partition" "info"

	# Find the pre-compiled DTB in the userpatches directory
	local dtb_src="${SRC}/userpatches/patch/kernel/${KERNELSourceType}-${KERNEL_MAJOR_MINOR}/dt/rockchip/rk3566-torder-tablet.dtb"
	local dtb_fallback="${SRC}/dtb/rockchip/rk3566-torder-tablet.dtb"
	local dtb_file=""

	if [[ -f "${dtb_src}" ]]; then
		dtb_file="${dtb_src}"
	elif [[ -f "${dtb_fallback}" ]]; then
		dtb_file="${dtb_fallback}"
	fi

	if [[ -n "${dtb_file}" && -f "${dtb_file}" ]]; then
		# Install to boot partition for all kernel versions
		for dtb_dir in "${SDCARD}/boot/dtb"*/rockchip "${SDCARD}/boot/dtb/rockchip"; do
			if [[ -d "$(dirname "${dtb_dir}")" ]]; then
				mkdir -p "${dtb_dir}" 2>/dev/null || true
				cp "${dtb_file}" "${dtb_dir}/rk3566-torder-tablet.dtb" 2>/dev/null || true
				display_alert "$BOARD" "Installed DTB to ${dtb_dir}" "info"
			fi
		done
	else
		display_alert "$BOARD" "Warning: DTB file not found, cannot install" "warn"
	fi
}
