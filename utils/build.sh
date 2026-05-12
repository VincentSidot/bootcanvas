#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
IMAGE_SRC="${IMAGE_SRC:-$ROOT_DIR/image/naturestock.jpg}"

STAGE1_SRC="$ROOT_DIR/src/stage1.s"
STAGE2_SRC="$ROOT_DIR/src/stage2.s"

IMAGE_BIN="$BUILD_DIR/image.bin"
STAGE1_BIN="$BUILD_DIR/stage1.bin"
STAGE2_BIN="$BUILD_DIR/stage2.bin"
BOOT_BIN="$BUILD_DIR/boot.bin"

run_fasm() {
    if command -v fasm >/dev/null 2>&1; then
        fasm "$@"
    else
        "$ROOT_DIR/utils/fasm.sh" "$@"
    fi
}

mkdir -p "$BUILD_DIR"

bash "$ROOT_DIR/utils/python.sh" python "$ROOT_DIR/utils/convert.py" "$IMAGE_SRC" "$IMAGE_BIN"
run_fasm "$STAGE2_SRC" "$STAGE2_BIN"

stage2_size_bytes="$(wc -c < "$STAGE2_BIN" | tr -d '[:space:]')"
image_size_bytes="$(wc -c < "$IMAGE_BIN" | tr -d '[:space:]')"
image_validation_value="$(od -An -tu2 -N2 "$IMAGE_BIN" | tr -d '[:space:]')"

run_fasm \
    -d "STAGE2_SIZE_B=${stage2_size_bytes}" \
    -d "IMAGE_SIZE_B=${image_size_bytes}" \
    -d "IMAGE_VALIDATION_VALUE=${image_validation_value}" \
    "$STAGE1_SRC" \
    "$STAGE1_BIN"

cat "$STAGE1_BIN" "$STAGE2_BIN" "$IMAGE_BIN" > "$BOOT_BIN"

printf 'Built %s\n' "$BOOT_BIN"
