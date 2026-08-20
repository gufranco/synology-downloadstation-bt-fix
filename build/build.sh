#!/usr/bin/env bash
set -euo pipefail

TRANSMISSION_VERSION="${TRANSMISSION_VERSION:-4.1.1}"
TARGET_ARCH="${TARGET_ARCH:-x86_64}"
BUILD_JOBS="${BUILD_JOBS:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/dist}"
ARTIFACT_SUFFIX="${ARTIFACT_SUFFIX:-dsfix}"
artifact_name="transmissiond-${TRANSMISSION_VERSION}-${ARTIFACT_SUFFIX}-${TARGET_ARCH}"

case "$TARGET_ARCH" in
  x86_64) docker_platform=linux/amd64 ;;
  aarch64) docker_platform=linux/arm64 ;;
  *)
    printf 'error: unsupported TARGET_ARCH: %s\n' "$TARGET_ARCH" >&2
    exit 2
    ;;
esac

container_name="dsfix-build-${TARGET_ARCH}-${TRANSMISSION_VERSION//./-}-$$"
cleanup_container() {
  docker stop "$container_name" >/dev/null 2>&1 || true
  docker rm "$container_name" >/dev/null 2>&1 || true
}
trap cleanup_container EXIT
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

mkdir -p "$OUTPUT_DIR"

printf 'building transmission-daemon %s for %s (jobs=%s)\n' \
  "$TRANSMISSION_VERSION" "$TARGET_ARCH" "$BUILD_JOBS"

patches_dir="${script_dir}/../patches"

[ -d "$patches_dir" ] || {
  printf 'error: patches directory not found: %s\n' "$patches_dir" >&2
  exit 2
}

docker run -i --name "$container_name" --platform "$docker_platform" \
  -e TRANSMISSION_VERSION="$TRANSMISSION_VERSION" \
  -e BUILD_JOBS="$BUILD_JOBS" \
  -v "$(cd -- "$patches_dir" && pwd):/patches:ro" \
  debian:12 bash -s <"${script_dir}/build-in-container.sh"

docker cp "${container_name}:/out/transmission-daemon" \
  "${OUTPUT_DIR}/${artifact_name}"

artifact="${OUTPUT_DIR}/${artifact_name}"
chmod 755 "$artifact"
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$artifact")" >"$(basename "$artifact").sha256")

printf 'artifact: %s\n' "$artifact"
cat "${artifact}.sha256"
