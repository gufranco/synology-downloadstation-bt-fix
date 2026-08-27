#!/usr/bin/env bash
set -euo pipefail

artifact="${1:?usage: check-linkage.sh <artifact> <arch>}"
arch="${2:?usage: check-linkage.sh <artifact> <arch>}"

case "$arch" in
  x86_64) loader=ld-linux-x86-64.so.2 ;;
  aarch64) loader=ld-linux-aarch64.so.1 ;;
  *)
    printf 'error: unsupported arch: %s\n' "$arch" >&2
    exit 2
    ;;
esac

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

printf '%s\n' "$loader" libc.so.6 libcrypto.so.3 libcurl.so.4 libm.so.6 libssl.so.3 |
  sort >"${workdir}/allowed"

readelf -d "$artifact" |
  awk '/NEEDED/ {gsub(/[\[\]]/, "", $5); print $5}' |
  sort >"${workdir}/needed"

if ! diff -u "${workdir}/allowed" "${workdir}/needed"; then
  printf 'error: %s links against a library DSM does not provide\n' "$artifact" >&2
  exit 1
fi

printf 'linkage ok (%s): only libraries DSM ships\n' "$arch"
