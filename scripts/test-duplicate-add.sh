#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/common.sh"

PROBE_TORRENT="${1:-}"

usage() {
  cat <<'USAGE'
Usage: sudo ./test-duplicate-add.sh <path-to-any-small-torrent>

Exercises the reply that DownloadStation depends on when it re-adds a
torrent the daemon already holds. Case 3 fails on a daemon without
0002-report-added-for-downloadstation-duplicate.patch, which is the
whole point: it reproduces the add-fail loop rather than describing it.

The torrent is added paused and removed afterwards with the data left
alone. Pick one whose payload is small or absent; the SBI subchannel and
BIOS image sets are good choices.
USAGE
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

  python3 - "$RPC_SOCKET" "$PROBE_TORRENT" <<'PYTHON'
import json
import socket
import sys

socket_path, torrent_path = sys.argv[1], sys.argv[2]
PROBE_ID, OTHER_ID = 9101, 9102
failures = []


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


def reply_kind(response):
    arguments = arguments_of(response)
    if "torrent-added" in arguments:
        return "torrent-added"
    if "torrent-duplicate" in arguments:
        return "torrent-duplicate"
    return "other"


def add(task_id):
    payload = {"filename": torrent_path, "paused": True}
    if task_id is not None:
        payload["task-id"] = task_id
    return call("torrent-add", payload)


def remove_probes():
    present = [
        t["id"]
        for t in arguments_of(call("torrent-get", {"fields": ["id"]})).get("torrents", [])
        if t["id"] in (PROBE_ID, OTHER_ID)
    ]
    if present:
        call("torrent-remove", {"ids": present, "delete-local-data": False})


def check(label, actual, expected):
    passed = actual == expected
    print("%-54s %-18s %s" % (label, actual, "PASS" if passed else "FAIL want " + expected))
    if not passed:
        failures.append(label)


remove_probes()

first = add(PROBE_ID)
check("1 first add with task-id", reply_kind(first), "torrent-added")
check(
    "2 torrent took the requested id",
    str(arguments_of(first).get("torrent-added", {}).get("id")),
    str(PROBE_ID),
)
check("3 re-add with same task-id", reply_kind(add(PROBE_ID)), "torrent-added")
check("4 re-add with a different task-id", reply_kind(add(OTHER_ID)), "torrent-duplicate")
check("5 re-add with no task-id", reply_kind(add(None)), "torrent-duplicate")
check(
    "6 torrent-get by task-id",
    "found" if arguments_of(call("torrent-get", {"ids": [PROBE_ID], "fields": ["id"]})).get("torrents") else "empty",
    "found",
)

remove_probes()

print()
print("RESULT: %s" % ("PASS" if not failures else "FAIL %s" % failures))
sys.exit(1 if failures else 0)
PYTHON
}

main "$@"
