#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/common.sh"

PROBE_TORRENT="${1:-}"

usage() {
  cat <<'USAGE'
Usage: sudo ./test-taskid-across-restart.sh <path-to-any-small-torrent>

Checks that a torrent keeps its DownloadStation task-id after the daemon
restarts. Without 0003-persist-task-id-across-daemon-restarts.patch the
daemon reloads its torrents directory and hands out sequential ids, so the
id DownloadStation asked for is gone and every later add loops.

This is the case test-duplicate-add.sh cannot see, because that script
adds and re-adds inside one daemon session.
USAGE
}

probe_id_after_restart() {
  python3 - "$RPC_SOCKET" "$1" "$2" <<'PYTHON'
import json
import socket
import sys

socket_path, torrent_path, mode = sys.argv[1], sys.argv[2], sys.argv[3]
PROBE_ID = 9311


def send(body, session_id):
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(120)
    connection.connect(socket_path)
    headers = [
        "POST /transmission/rpc HTTP/1.1",
        "Host: localhost",
        "Content-Type: application/json",
        "Content-Length: %d" % len(body),
        "Connection: close",
    ]
    if session_id:
        headers.append("X-Transmission-Session-Id: %s" % session_id)
    connection.sendall(("\r\n".join(headers) + "\r\n\r\n").encode("ascii") + body)
    chunks = []
    while True:
        chunk = connection.recv(65536)
        if not chunk:
            break
        chunks.append(chunk)
    connection.close()
    return b"".join(chunks)


def parse(raw):
    head, _, payload = raw.partition(b"\r\n\r\n")
    status_line = head.split(b"\r\n", 1)[0].decode("ascii", "replace")
    session_id = ""
    for line in head.decode("ascii", "replace").split("\r\n"):
        if line.lower().startswith("x-transmission-session-id:"):
            session_id = line.split(":", 1)[1].strip()
    if b"hunked" in head:
        decoded, rest = b"", payload
        while rest:
            size_line, _, rest = rest.partition(b"\r\n")
            try:
                size = int(size_line.strip().split(b";")[0], 16)
            except ValueError:
                break
            if size == 0:
                break
            decoded += rest[:size]
            rest = rest[size + 2:]
        payload = decoded
    return status_line, session_id, payload


def call(method, arguments):
    body = json.dumps({"method": method, "arguments": arguments}).encode("utf-8")
    status_line, session_id, payload = parse(send(body, ""))
    if "409" in status_line:
        _, _, payload = parse(send(body, session_id))
    return json.loads(payload.decode("utf-8", "replace"))


def arguments_of(response):
    return response.get("arguments", response.get("data", {}))


if mode == "setup":
    present = [
        t["id"]
        for t in arguments_of(call("torrent-get", {"fields": ["id"]})).get("torrents", [])
        if t["id"] == PROBE_ID
    ]
    if present:
        call("torrent-remove", {"ids": present, "delete-local-data": False})
    response = call(
        "torrent-add", {"filename": torrent_path, "paused": True, "task-id": PROBE_ID}
    )
    added = arguments_of(response).get("torrent-added")
    if added is None:
        print("SETUP FAILED: %s" % json.dumps(response)[:200])
        sys.exit(1)
    print("setup: added with id %s" % added["id"])
    sys.exit(0 if added["id"] == PROBE_ID else 1)

found = [
    t
    for t in arguments_of(call("torrent-get", {"fields": ["id", "hashString"]})).get("torrents", [])
    if t["id"] == PROBE_ID
]
print("after restart: id %d %s" % (PROBE_ID, "PRESENT" if found else "MISSING"))
if not found:
    print("RESULT: FAIL, the daemon renumbered it on load")
    sys.exit(1)

kind = "torrent-added" if "torrent-added" in arguments_of(
    call("torrent-add", {"filename": torrent_path, "paused": True, "task-id": PROBE_ID})
) else "torrent-duplicate"
print("re-add after restart: %s" % kind)

call("torrent-remove", {"ids": [PROBE_ID], "delete-local-data": False})
print("RESULT: %s" % ("PASS" if kind == "torrent-added" else "FAIL"))
sys.exit(0 if kind == "torrent-added" else 1)
PYTHON
}

main() {
  require_root
  require_downloadstation

  [ -n "$PROBE_TORRENT" ] || {
    usage
    exit 2
  }
  [ -f "$PROBE_TORRENT" ] || die "torrent not found: ${PROBE_TORRENT}"
  [ -S "$RPC_SOCKET" ] || die "transmissiond is not running; start a BT task first"

  probe_id_after_restart "$PROBE_TORRENT" setup

  log "restarting the daemon"
  systemctl restart "$DAEMON_UNIT"
  wait_for_rpc_socket 120 || die "daemon did not come back"
  sleep 5

  probe_id_after_restart "$PROBE_TORRENT" check
}

main "$@"
