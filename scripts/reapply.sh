#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/common.sh"

patch_is_active() {
  [ -f "$INSTALLED_MARKER" ] || return 1
  recorded_md5=$(awk -F= '/^patched_md5=/{print $2}' "$INSTALLED_MARKER")
  [ -n "$recorded_md5" ] || return 1
  [ "$recorded_md5" = "$(checksum_of "$TARGET_BIN")" ]
}

reinstall_patched_binary() {
  [ -f "$PATCHED_COPY" ] || die "no stored patched binary at ${PATCHED_COPY}; re-run install.sh"

  owner="$DAEMON_OWNER"
  mode="$DAEMON_MODE"

  stop_downloadstation

  if [ ! -f "$STOCK_BACKUP" ] || [ "$(checksum_of "$TARGET_BIN")" != "$(checksum_of "$PATCHED_COPY")" ]; then
    cp -f "$TARGET_BIN" "$STOCK_BACKUP"
  fi

  cp -f "$PATCHED_COPY" "${TARGET_BIN}.new"
  chown "$owner" "${TARGET_BIN}.new" 2>/dev/null || true
  chmod "$mode" "${TARGET_BIN}.new"
  mv -f "${TARGET_BIN}.new" "$TARGET_BIN"

  start_downloadstation
  log "re-applied patched daemon: $(daemon_version_of "$TARGET_BIN")"
}

main() {
  require_root
  require_downloadstation

  install_shutdown_grace

  if patch_is_active; then
    log "patch already active; nothing to do"
    exit 0
  fi

  log "patched daemon is not active; re-applying"
  reinstall_patched_binary

  if wait_for_rpc_socket 40 && [ "$(probe_rpc 25 | cut -d' ' -f1)" = "RESPONSE" ]; then
    log "re-apply verified"
    exit 0
  fi

  warn "re-apply finished but RPC did not answer"
  exit 1
}

main "$@"
