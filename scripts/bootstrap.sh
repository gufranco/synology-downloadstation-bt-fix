#!/bin/sh
set -eu

REPO=gufranco/synology-downloadstation-bt-fix
RELEASE="${DSFIX_RELEASE:-latest}"
WORKDIR=""

log() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [ -n "$WORKDIR" ] && rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

require_root() {
  [ "$(id -u)" = "0" ] || die "run this with sudo"
}

require_dsm() {
  [ -f /etc/synoinfo.conf ] || die "this is not a Synology DSM system"
  [ -d /var/packages/DownloadStation ] || die "DownloadStation is not installed"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64) printf 'x86_64\n' ;;
    aarch64) printf 'aarch64\n' ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

resolve_tag() {
  if [ "$RELEASE" != "latest" ]; then
    printf '%s\n' "$RELEASE"
    return
  fi
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null ||
    die "could not reach the GitHub API to find the latest release"
}

sha256_of() {
  python3 -c '
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as fh:
    for chunk in iter(lambda: fh.read(1 << 20), b""):
        h.update(chunk)
print(h.hexdigest())
' "$1"
}

fetch_and_verify() {
  arch="$1"
  tag="$2"
  base="https://github.com/${REPO}/releases/download/${tag}"
  name="transmissiond-4.1.1-dsfix-${arch}"

  log "downloading ${name} (${tag})"
  curl -fsSL --retry 3 -o "${WORKDIR}/${name}" "${base}/${name}" ||
    die "download failed; check that ${tag} has an asset for ${arch}"
  curl -fsSL --retry 3 -o "${WORKDIR}/${name}.sha256" "${base}/${name}.sha256" ||
    die "checksum file missing for ${tag}"

  expected=$(awk '{print $1}' "${WORKDIR}/${name}.sha256")
  actual=$(sha256_of "${WORKDIR}/${name}")
  [ -n "$expected" ] || die "checksum file was empty"
  if [ "$expected" != "$actual" ]; then
    warn "expected ${expected}"
    warn "actual   ${actual}"
    die "checksum mismatch, refusing to install"
  fi
  log "sha256 verified: ${actual}"
  printf '%s\n' "${WORKDIR}/${name}"
}

fetch_scripts() {
  tag="$1"
  log "fetching the installer scripts for ${tag}"
  curl -fsSL --retry 3 -o "${WORKDIR}/src.tar.gz" \
    "https://github.com/${REPO}/archive/refs/tags/${tag}.tar.gz" ||
    die "could not fetch the source tarball"
  tar xzf "${WORKDIR}/src.tar.gz" -C "$WORKDIR" || die "could not unpack the source tarball"
  found=$(find "$WORKDIR" -type d -name scripts | head -1)
  [ -n "$found" ] || die "the tarball had no scripts directory"
  chmod 755 "$found"/*.sh
  printf '%s\n' "$found"
}

main() {
  require_root
  require_dsm

  command -v curl >/dev/null 2>&1 || die "curl not found"
  command -v python3 >/dev/null 2>&1 || die "python3 not found"

  arch=$(detect_arch)
  tag=$(resolve_tag)
  WORKDIR=$(mktemp -d /tmp/dsfix-install-XXXXXX)

  log "architecture: ${arch}"
  log "release:      ${tag}"

  binary=$(fetch_and_verify "$arch" "$tag")
  scripts=$(fetch_scripts "$tag")

  log ""
  "${scripts}/install.sh" "$binary"

  log ""
  log "registering the boot task so a DownloadStation update cannot undo this"
  "${scripts}/install-boot-task.sh" || warn "boot task registration failed; run install-boot-task.sh by hand"

  log ""
  log "done. check it with:"
  log "  sudo /var/packages/DownloadStation/etc/dsfix/scripts/verify.sh"
}

main "$@"
