#!/usr/bin/env bash

set -euo pipefail

host_root="$(pwd)"
container_root="/work"
image_name="bootcanvas-fasm:local"
dockerfile_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../docker" && pwd)"
args=()

# Translate host paths to container paths for arguments that are within the host
# root directory
for arg in "$@"; do
    case "$arg" in
        "$host_root"/*)
            args+=("${container_root}/${arg#"$host_root"/}")
            ;;
        *)
            args+=("$arg")
            ;;
    esac
done

# Build the Docker image if it doesn't exist
if ! docker image inspect "$image_name" >/dev/null 2>&1; then
    docker build -t "$image_name" "$dockerfile_dir"
fi

set -x
docker run --rm -v "${host_root}:${container_root}" -w "$container_root" "$image_name" "${args[@]}"
