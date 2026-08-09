#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/common.sh"

SCHEDULER_DB=/usr/syno/etc/esynoscheduler/esynoscheduler.db
SCHEDULER_DB_BACKUP="${SCHEDULER_DB}.bak-dsfix"
TASK_NAME="dsfix reapply transmissiond"
TASK_DESCRIPTION="Re-applies the patched transmissiond after a DownloadStation update"
INSTALLED_SCRIPTS_DIR="${STATE_DIR}/scripts"
BOOT_SCRIPT="${INSTALLED_SCRIPTS_DIR}/reapply.sh"

require_sqlite() {
  command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found; cannot register the boot task"
  [ -f "$SCHEDULER_DB" ] || die "scheduler database not found at ${SCHEDULER_DB}"
}

install_scripts() {
  mkdir -p "$INSTALLED_SCRIPTS_DIR"
  for name in common.sh install.sh uninstall.sh verify.sh reapply.sh; do
    cp -f "${SCRIPT_DIR}/${name}" "${INSTALLED_SCRIPTS_DIR}/${name}"
  done
  chmod 755 "${INSTALLED_SCRIPTS_DIR}"/*.sh
  log "scripts installed to ${INSTALLED_SCRIPTS_DIR}"
}

task_exists() {
  count=$(sqlite3 "$SCHEDULER_DB" "SELECT COUNT(*) FROM task WHERE task_name = '${TASK_NAME}';" 2>/dev/null || printf '0\n')
  [ "$count" != "0" ]
}

register_task() {
  cp -f "$SCHEDULER_DB" "$SCHEDULER_DB_BACKUP"
  log "scheduler database backed up to ${SCHEDULER_DB_BACKUP}"

  sqlite3 "$SCHEDULER_DB" "INSERT INTO task (task_name, description, event, depend_on_task, enable, owner, run_the_same_time, notify_enable, notify_mail, notify_if_error, operation, operation_type) VALUES ('${TASK_NAME}', '${TASK_DESCRIPTION}', 'bootup', '', 1, 0, 1, 0, '', 0, '${BOOT_SCRIPT}', 'script');"

  synoschedtask --sync >/dev/null 2>&1 || true
  log "boot task registered"
}

main() {
  require_root
  require_downloadstation
  require_sqlite

  install_scripts

  if task_exists; then
    log "boot task already registered; nothing to do"
    exit 0
  fi

  register_task

  if task_exists; then
    log "done; the fix will be re-applied automatically after every reboot"
    log "it appears in Control Panel > Task Scheduler as: ${TASK_NAME}"
    exit 0
  fi

  die "registration did not take effect"
}

main "$@"
