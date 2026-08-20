# Working on this repository

Notes for anyone, human or agent, changing this project. It is short on
process and long on the specific traps this codebase has already sprung,
because every one of them produced a fix that looked correct and was not.

## What this project is

A replacement `transmission-daemon` for Synology DownloadStation, plus the
scripts that install it and prove it works. The daemon is GPL software we
modify, so the patches and the exact build recipe are part of the deliverable,
not an implementation detail.

Five defects have to be addressed together. Three stop BitTorrent working at
all; two decide whether the fix survives a restart. [README.md](README.md)
explains each and why none is sufficient alone.

## The rule that matters most

**A test that passes is not evidence until you have watched it fail.**

This is not a general principle here, it is a scar. `scripts/test-duplicate-add.sh`
passed against a daemon that still looped in production, because it added and
re-added a torrent inside one daemon session and never restarted anything. The
id it asserted on was the id the add had just set. The bug lived in the restart
path the test could not reach, and the green result was read as proof.

So, before claiming any fix works:

1. Run the test against the **unfixed** build and confirm it fails.
2. Read the failure. If it fails for a different reason than the bug, the test
   is wrong.
3. Only then apply the fix and re-run.

A test committed without a recorded failing baseline is a test nobody can
trust. The commit message for `test-duplicate-add.sh` records its baseline
output for exactly this reason; do the same.

## Environment facts that break assumptions

DSM is not a general Linux box. These are verified, not folklore.

| Assumption | Reality on DSM 7.3 |
|---|---|
| `pgrep` exists | It does not. The scripts parse `ps` instead |
| `sha256sum` exists | It does not. `md5sum` does, which is why checksums are recorded in both |
| `strings`, `readelf` exist | They do not. Use `python3` for binary inspection |
| `scp` works | It does not. Push payloads over the ssh channel instead |
| `/tmp` is executable | It is mounted `noexec`. Stage binaries inside the package directory |
| A path is a path | `local_path` in the DownloadStation API must be **share-relative**, never absolute |
| Root is root | `synowebapi` run as root creates tasks owned by `SYSTEM_ADMIN`, which the scheduler silently never processes. Pass `runner=<user>` |

That last pair cost hours. Both fail by doing nothing rather than by erroring.

## The daemon's id model

DownloadStation passes its own task number to `torrent-add` as a private
`task-id` argument and then looks the torrent up **by that number**. Everything
in the patch set exists to keep that lookup working.

- Patch 1 places the torrent at the requested id.
- Patch 3 persists that id in a `<info-hash>.taskid` sidecar so it survives a
  restart, because the loader would otherwise renumber every torrent
  sequentially.
- Patch 2 makes the duplicate reply correct once the id is reliably right.

Change one and you almost certainly need to think about the other two.

**Upgrading an existing install:** a torrent added before patch 3 has no
sidecar, so the first restart renumbers it anyway. Seed the sidecars from the
live id mapping before restarting, or re-add each torrent once. A restart test
run without doing this fails for a reason unrelated to the patch.

## Changing a patch

Patches are plain unified diffs against the upstream tarball, applied in
filename order. Do not hand-write hunk headers; the line counts will be wrong
and `patch` rejects the file. Generate them:

```sh
mkdir -p /tmp/p/a /tmp/p/b
# extract the tarball into each, apply the preceding patches to both,
# edit only b, then:
diff -u a/transmission-4.1.1/libtransmission/foo.cc \
        b/transmission-4.1.1/libtransmission/foo.cc \
  | sed -e '1s|.*|--- a/libtransmission/foo.cc|' \
        -e '2s|.*|+++ b/libtransmission/foo.cc|'
```

Then confirm every patch still applies to a pristine tree, in order. CI does
this on every push, and it is the check that catches patch rot when upstream
moves.

## Building

```sh
TARGET_ARCH=x86_64 BUILD_JOBS=4 ./build/build.sh
```

The build runs in `debian:12`, which matches DSM's glibc 2.36 and GCC 12.
Bundled third-party libraries are linked statically because DSM's sonames do
not line up; the binary must end up needing only the six libraries DSM ships,
and CI fails the build if a seventh appears.

Under QEMU emulation on an ARM host, use `BUILD_JOBS=1`. Higher values
segfault the compiler partway through vendored `libdeflate`. That failure is
not your code, and it happens far below the transmission targets.

**Check the artifact, not the exit code.** A shell pipeline reports the status
of its last command, so a failed build followed by a `tail` looks like success.
Confirm the artifact exists and its checksum changed.

## Verification

Nothing here is verified by reading it. In rough order of cost:

| Check | Command |
|---|---|
| Patch state, socket group, stop timeout, live RPC | `sudo ./scripts/verify.sh` |
| Duplicate reply within one session | `sudo ./scripts/test-duplicate-add.sh <torrent>` |
| Task id survives a restart | `sudo ./scripts/test-taskid-across-restart.sh <torrent>` |

`RESPONSE HTTP/1.1 409 Conflict` from the RPC probe is a pass: 409 is
Transmission asking for a session id, which proves the handler ran and replied.
The broken daemon returns `NO_RESPONSE timeout`.

## Touching a live NAS

- The payload data is the thing that matters. `torrent-remove` with
  `delete-local-data: false` preserves payload but **deletes the resume and
  torrent metadata**, so verification progress is lost. Back up
  `<config-dir>/resume` first if that progress is expensive.
- Restoring a `.resume` file before re-adding preserves progress, because
  Transmission looks it up by info-hash rather than by id.
- The transmission monitor stops the daemon after roughly a minute with no
  active task, which will interrupt maintenance. Mask it for the window and
  unmask it immediately afterwards; a mask survives reboots.
- Deleting a DownloadStation task is not obviously safe when several torrents
  share a payload directory name. Prefer the UI, which shows what it will
  remove.

## What good looks like here

- A claim in the documentation names the evidence behind it. The shutdown
  timings in [REFERENCE.md](REFERENCE.md) are measured values with the method
  written down, not estimates.
- A number in a table came from a command someone ran.
- A fix ships with a test that failed before it.
- Prose says what is verified and what is assumed, separately.
