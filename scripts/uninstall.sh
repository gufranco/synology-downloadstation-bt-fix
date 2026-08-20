#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/common.sh"

restore_stock_binary() {
  [ -f "$STOCK_BACKUP" ] || die "no stock backup found at ${STOCK_BACKUP}; nothing to restore"

  owner="$DAEMON_OWNER"
  mode="$STOCK_MODE"

  cp -f "$STOCK_BACKUP" "${TARGET_BIN}.restore"
  chown "$owner" "${TARGET_BIN}.restore" 2>/dev/null || true
  chmod "$mode" "${TARGET_BIN}.restore"
  mv -f "${TARGET_BIN}.restore" "$TARGET_BIN"
  log "restored stock binary: $(daemon_version_of "$TARGET_BIN")"
}

discard_state() {
  rm -f "$INSTALLED_MARKER" "$PATCHED_COPY"
  rm -rf "$INSTALLED_SCRIPTS_DIR"
  rmdir "$STATE_DIR" 2>/dev/null || true
}

main() {
  require_root
  require_downloadstation

  log "current daemon: $(daemon_version_of "$TARGET_BIN")"

  remove_boot_task || true

  stop_downloadstation
  restore_stock_binary
  remove_shutdown_grace
  start_downloadstation

  discard_state

  log "uninstall complete; the stock daemon is active again"
  log "note: the stock daemon does not answer RPC over the domain socket, so BT tasks will fail again"
}

main "$@"
