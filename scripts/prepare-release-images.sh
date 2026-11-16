#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# GitHub requires each release asset to be strictly smaller than 2 GiB.
max_asset_bytes=$((2 * 1024 * 1024 * 1024 - 1))

for image in "$@"; do
    test -s "$image"
    image_size=$(stat -c %s -- "$image")
    original_checksum=$(sha256sum -- "$image")
    printf '%s\n' "$original_checksum" > "$image.sha256"

    if (( image_size > max_asset_bytes )); then
        split --bytes="$max_asset_bytes" --numeric-suffixes=1 --suffix-length=3 -- \
            "$image" "$image.part-"
        parts=("$image".part-[0-9][0-9][0-9])
        sha256sum -- "${parts[@]}" > "$image.parts.sha256"
        sha256sum --check "$image.parts.sha256"

        reassembled_checksum=$(cat -- "${parts[@]}" | sha256sum)
        if [[ "${original_checksum%% *}" != "${reassembled_checksum%% *}" ]]; then
            printf 'Reassembled image checksum mismatch: %s\n' "$image" >&2
            exit 1
        fi
        rm -- "$image"
    fi
done
