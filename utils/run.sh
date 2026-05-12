#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT_BIN="$ROOT_DIR/build/boot.bin"

if [ ! -f "$BOOT_BIN" ]; then
    "$ROOT_DIR/utils/build.sh"
fi

qemu-system-i386 -drive format=raw,file="$BOOT_BIN"
