#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/common.sh"

report_binaries() {
  log "active daemon:  $(daemon_version_of "$TARGET_BIN")"
  log "active md5:     $(checksum_of "$TARGET_BIN")"
  if [ -f "$STOCK_BACKUP" ]; then
    log "stock backup:   $(daemon_version_of "$STOCK_BACKUP")"
    log "stock md5:      $(checksum_of "$STOCK_BACKUP")"
  else
    log "stock backup:   absent"
  fi
}

report_patch_state() {
  [ -f "$INSTALLED_MARKER" ] || {
    log "patch state:    not installed by this tool"
    return 0
  }

  recorded_md5=$(awk -F= '/^patched_md5=/{print $2}' "$INSTALLED_MARKER")
  current_md5=$(checksum_of "$TARGET_BIN")

  if [ "$recorded_md5" = "$current_md5" ]; then
    log "patch state:    ACTIVE"
    return 0
  fi

  warn "patch state:    OVERWRITTEN"
  warn "the active binary no longer matches the one this tool installed."
  warn "a DownloadStation package update most likely replaced it; re-run install.sh"
  return 1
}

report_rpc() {
  if ! downloadstation_is_running; then
    warn "rpc probe:      SKIPPED (DownloadStation is not running)"
    warn "verdict:        INCONCLUSIVE"
    return 2
  fi

  if [ ! -S "$RPC_SOCKET" ]; then
    warn "rpc probe:      SKIPPED (transmissiond is not running)"
    warn "                DownloadStation starts it only while a BT task exists."
    warn "                Add any torrent, then re-run this script."
    warn "verdict:        INCONCLUSIVE"
    return 2
  fi

  probe_result=$(probe_rpc 25 || true)
  log "rpc probe:      ${probe_result}"
  case "$probe_result" in
    RESPONSE*)
      log "verdict:        PASS"
      return 0
      ;;
    *)
      warn "verdict:        FAIL"
      return 1
      ;;
  esac
}

main() {
  require_root
  require_downloadstation

  report_binaries

  patch_ok=0
  report_patch_state || patch_ok=1

  rpc_status=0
  report_rpc || rpc_status=$?

  [ "$patch_ok" = "0" ] || exit 1
  [ "$rpc_status" = "0" ] && exit 0
  [ "$rpc_status" = "2" ] && exit 2
  exit 1
}

main "$@"
