#!/usr/bin/env bash

set -euo pipefail

PYLIBFDT_VERSION="1.7.2.post1"
PYLIBFDT_FIXED_VERSION="1.7.2.post1+dtc5008d1d6"
PYLIBFDT_ARCHIVE_SHA256="08ec69755f7565dc25e4e640e0315795888d4caeb7f146de4e05bf12b03c94c8"
PYLIBFDT_FIX_COMMIT="5008d1d6a356b8d0a78060da2e1021507d529cff"
PYLIBFDT_ARCHIVE_URL="https://files.pythonhosted.org/packages/a2/b8/ef881f0e76af7727ca9c5e27a121db69667c69e4e91eceaafe97f3666a6c/pylibfdt-${PYLIBFDT_VERSION}.tar.gz"

usage() {
	printf 'Usage: %s <armbian-build-directory> [work-directory]\n' "$0" >&2
	exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

armbian_dir="$(realpath "$1")"
requirements_file="${armbian_dir}/requirements.txt"
work_dir="${2:-${armbian_dir}/cache/pylibfdt-fixed}"

[[ -f "${requirements_file}" ]] || {
	printf 'Armbian requirements file not found: %s\n' "${requirements_file}" >&2
	exit 1
}

mkdir -p "${work_dir}"
work_dir="$(realpath "${work_dir}")"
archive="${work_dir}/pylibfdt-${PYLIBFDT_VERSION}.tar.gz"
source_dir="${work_dir}/source"
wheel_dir="${work_dir}/wheel"
unpack_dir="${work_dir}/unpack"

rm -rf "${source_dir}" "${wheel_dir}" "${unpack_dir}"
mkdir -p "${source_dir}" "${wheel_dir}" "${unpack_dir}"

curl --fail --location --retry 3 --silent --show-error \
	--output "${archive}" "${PYLIBFDT_ARCHIVE_URL}"
printf '%s  %s\n' "${PYLIBFDT_ARCHIVE_SHA256}" "${archive}" | sha256sum --check -
tar -xzf "${archive}" -C "${source_dir}" --strip-components=1

interface_file="${source_dir}/libfdt/libfdt.i"
old_line="   depth = (int) PyInt_AsLong(\$input);"
new_line="   depth = (int) PyLong_AsLong(\$input);"

[[ "$(grep -Fxc "${old_line}" "${interface_file}")" -eq 1 ]]
sed -i "s/PyInt_AsLong/PyLong_AsLong/" "${interface_file}"
[[ "$(grep -Fxc "${new_line}" "${interface_file}")" -eq 1 ]]
if grep -Fq 'PyInt_AsLong' "${interface_file}"; then
	printf 'Unpatched PyInt_AsLong reference remains in %s\n' "${interface_file}" >&2
	exit 1
fi

SETUPTOOLS_SCM_PRETEND_VERSION_FOR_PYLIBFDT="${PYLIBFDT_FIXED_VERSION}" \
	PIP_DISABLE_PIP_VERSION_CHECK=1 python3 -m pip wheel \
	--no-cache-dir --no-deps --wheel-dir "${wheel_dir}" "${source_dir}"

mapfile -t wheels < <(find "${wheel_dir}" -maxdepth 1 -type f -name 'pylibfdt-*.whl' -print)
[[ "${#wheels[@]}" -eq 1 ]]
wheel="${wheels[0]}"

unzip -q "${wheel}" -d "${unpack_dir}"
mapfile -t metadata_files < <(find "${unpack_dir}" -maxdepth 2 -type f \
	-path '*/pylibfdt-*.dist-info/METADATA' -print)
[[ "${#metadata_files[@]}" -eq 1 ]]
grep -Fxq "Version: ${PYLIBFDT_FIXED_VERSION}" "${metadata_files[0]}"
mapfile -t modules < <(find "${unpack_dir}" -maxdepth 1 -type f -name '_libfdt*.so' -print)
[[ "${#modules[@]}" -eq 1 ]]
module="${modules[0]}"
symbols_file="${work_dir}/pylibfdt-symbols.txt"
nm -D "${module}" > "${symbols_file}"

if grep -Fq 'PyInt_AsLong' "${symbols_file}"; then
	printf 'Fixed pylibfdt still imports PyInt_AsLong: %s\n' "${module}" >&2
	exit 1
fi
grep -Fq 'PyLong_AsLong' "${symbols_file}"
PYTHONPATH="${unpack_dir}" python3 -c \
	'import libfdt; assert libfdt.Fdt; print("pylibfdt import OK:", libfdt.__file__)'

if grep -Eq '^[[:space:]]*pylibfdt([[:space:]]|@|=)' "${requirements_file}"; then
	printf 'Armbian requirements already pin pylibfdt: %s\n' "${requirements_file}" >&2
	exit 1
fi
printf '\n# Python 3 fix from dtc commit %s\n' "${PYLIBFDT_FIX_COMMIT}" >> "${requirements_file}"
printf 'pylibfdt @ file://%s\n' "${wheel}" >> "${requirements_file}"

printf 'Pinned fixed pylibfdt wheel: %s\n' "${wheel}"
