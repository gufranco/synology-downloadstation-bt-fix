#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/common.sh"

REPLACEMENT_BIN="${1:-}"
CANDIDATE_BIN="${SBIN_DIR}/transmissiond.candidate"

usage() {
  cat <<'USAGE'
Usage: sudo ./install.sh <path-to-replacement-transmissiond>

Replaces the DownloadStation transmissiond daemon with a build whose
Unix-socket RPC handler answers requests, keeping the stock binary as a
restorable backup.
USAGE
}

stage_candidate() {
  [ -n "$REPLACEMENT_BIN" ] || {
    usage
    exit 2
  }
  [ -f "$REPLACEMENT_BIN" ] || die "replacement binary not found: ${REPLACEMENT_BIN}"

  head -c 4 "$REPLACEMENT_BIN" | od -An -c | tr -d ' \n' | grep -q 'ELF' ||
    die "replacement is not an ELF binary: ${REPLACEMENT_BIN}"

  cp -f "$REPLACEMENT_BIN" "$CANDIDATE_BIN"
  chmod 755 "$CANDIDATE_BIN"
}

validate_candidate() {
  version_line=$(daemon_version_of "$CANDIDATE_BIN" 2>&1 || true)

  case "$version_line" in
    *transmission-daemon*)
      log "replacement reports: ${version_line}"
      ;;
    *"error while loading shared libraries"*)
      rm -f "$CANDIDATE_BIN"
      die "replacement cannot load on this DSM: ${version_line}"
      ;;
    *)
      rm -f "$CANDIDATE_BIN"
      die "replacement does not identify as transmission-daemon; refusing to install"
      ;;
  esac
}

back_up_stock_binary() {
  if [ -f "$STOCK_BACKUP" ]; then
    log "stock backup already present, leaving it untouched: ${STOCK_BACKUP}"
    return 0
  fi
  cp -f "$TARGET_BIN" "$STOCK_BACKUP"
  log "stock binary backed up to ${STOCK_BACKUP}"
}

promote_candidate() {
  chown "$DAEMON_OWNER" "$CANDIDATE_BIN" 2>/dev/null || true
  chmod "$DAEMON_MODE" "$CANDIDATE_BIN"
  mv -f "$CANDIDATE_BIN" "$TARGET_BIN"
  log "installed replacement into ${TARGET_BIN} (mode ${DAEMON_MODE})"
}

record_state() {
  mkdir -p "$STATE_DIR"
  cp -f "$TARGET_BIN" "$PATCHED_COPY"
  chmod 755 "$PATCHED_COPY"
  cat >"$INSTALLED_MARKER" <<EOF
patched_md5=$(checksum_of "$TARGET_BIN")
stock_md5=$(checksum_of "$STOCK_BACKUP")
patched_version=$(daemon_version_of "$TARGET_BIN")
stock_version=$(daemon_version_of "$STOCK_BACKUP")
arch=$(detect_arch)
EOF
  log "state recorded at ${INSTALLED_MARKER}"
}

verify_runtime() {
  if ! wait_for_rpc_socket 40; then
    warn "transmissiond did not start, so the fix could not be exercised yet."
    warn "DownloadStation runs it only while a BT task exists."
    warn "Add any torrent, then run ./verify.sh to confirm."
    return 2
  fi

  probe_result=$(probe_rpc 25 || true)
  log "rpc probe: ${probe_result}"
  case "$probe_result" in
    RESPONSE*)
      log "PASS: transmissiond answers RPC over the domain socket"
      return 0
      ;;
    *)
      warn "FAIL: transmissiond still does not answer RPC"
      return 1
      ;;
  esac
}

main() {
  require_root
  require_downloadstation

  log "architecture: $(detect_arch)"
  log "current daemon: $(daemon_version_of "$TARGET_BIN")"

  stage_candidate
  validate_candidate

  install_shutdown_grace
  stop_downloadstation
  back_up_stock_binary
  promote_candidate
  start_downloadstation

  record_state

  verify_status=0
  verify_runtime || verify_status=$?

  case "$verify_status" in
    0)
      log "install complete and verified"
      exit 0
      ;;
    2)
      log "install complete; verification pending a BT task"
      exit 0
      ;;
    *)
      warn "verification failed; run ./uninstall.sh to restore the stock binary"
      exit 1
      ;;
  esac
}

main "$@"
