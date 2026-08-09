#!/bin/sh
# shellcheck disable=SC2034

PATH=/usr/syno/bin:/usr/syno/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

PKG_DIR=/var/packages/DownloadStation
SBIN_DIR="${PKG_DIR}/target/sbin"
TARGET_BIN="${SBIN_DIR}/transmissiond"
STOCK_BACKUP="${SBIN_DIR}/transmissiond.stock"
STATE_DIR="${PKG_DIR}/etc/dsfix"
INSTALLED_MARKER="${STATE_DIR}/installed.conf"
PATCHED_COPY="${STATE_DIR}/transmissiond.patched"
RPC_SOCKET=/tmp/synodl_transmission.sock
DAEMON_STOP_TIMEOUT_SECONDS=15

log()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" = "0" ] || die "must run as root; re-run with sudo"
}

require_downloadstation() {
  [ -f /etc/synoinfo.conf ] || die "not a Synology DSM system"
  [ -d "$PKG_DIR" ] || die "DownloadStation is not installed"
  [ -f "$TARGET_BIN" ] || die "transmissiond not found at ${TARGET_BIN}"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64)  printf 'x86_64\n' ;;
    aarch64) printf 'aarch64\n' ;;
    *)       die "unsupported architecture: $(uname -m)" ;;
  esac
}

daemon_version_of() {
  "$1" --version 2>&1 | head -1
}

checksum_of() {
  md5sum "$1" 2>/dev/null | awk '{print $1}'
}

downloadstation_is_running() {
  synopkg is_onoff DownloadStation 2>/dev/null | grep -q "is turned on"
}

transmissiond_is_running() {
  ps aux 2>/dev/null | grep -q '[s]bin/transmissiond'
}

stop_downloadstation() {
  log "stopping DownloadStation"
  synopkg stop DownloadStation >/dev/null 2>&1 || true
  elapsed=0
  while [ "$elapsed" -lt "$DAEMON_STOP_TIMEOUT_SECONDS" ]; do
    transmissiond_is_running || return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  pkill -f 'sbin/transmissiond' >/dev/null 2>&1 || true
  sleep 1
}

start_downloadstation() {
  log "starting DownloadStation"
  synopkg start DownloadStation >/dev/null 2>&1 || true
}

wait_for_rpc_socket() {
  timeout_seconds="${1:-30}"
  elapsed=0
  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    [ -S "$RPC_SOCKET" ] && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

probe_rpc() {
  timeout_seconds="${1:-20}"
  [ -S "$RPC_SOCKET" ] || { warn "rpc socket absent: ${RPC_SOCKET}"; return 2; }
  python3 - "$RPC_SOCKET" "$timeout_seconds" <<'PYTHON'
import socket
import sys

socket_path, timeout_seconds = sys.argv[1], float(sys.argv[2])
connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
connection.settimeout(timeout_seconds)
request = (
    b"GET /transmission/rpc HTTP/1.1\r\n"
    b"Host: localhost\r\n"
    b"Accept: */*\r\n"
    b"Connection: close\r\n\r\n"
)
try:
    connection.connect(socket_path)
    connection.sendall(request)
    response = connection.recv(4096)
except Exception as error:
    print("NO_RESPONSE %s" % type(error).__name__)
    sys.exit(1)
finally:
    connection.close()

if not response:
    print("NO_RESPONSE empty")
    sys.exit(1)

print("RESPONSE %s" % response.split(b"\r\n", 1)[0].decode("ascii", "replace"))
PYTHON
}
