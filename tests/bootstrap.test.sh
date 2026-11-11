#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
BOOTSTRAP="$HERE/../scripts/bootstrap.sh"
SANDBOX=$(mktemp -d)
TAG=v9.9.9
ARCH=x86_64

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'ok: %s\n' "$*"
}

load_bootstrap_functions() {
  # shellcheck disable=SC2016
  [ "$(tail -n 1 "$BOOTSTRAP")" = 'main "$@"' ] ||
    fail "bootstrap.sh no longer ends by calling main"
  sed '$d' "$BOOTSTRAP" >"$SANDBOX/functions.sh"
  # shellcheck disable=SC1091
  . "$SANDBOX/functions.sh"
  trap 'rm -rf "$SANDBOX"' EXIT INT TERM
}

make_fixtures() {
  mkdir -p "$SANDBOX/source/synology-downloadstation-bt-fix-9.9.9/scripts" "$SANDBOX/bin"
  printf '#!/bin/sh\n' >"$SANDBOX/source/synology-downloadstation-bt-fix-9.9.9/scripts/install.sh"
  tar czf "$SANDBOX/source.tar.gz" -C "$SANDBOX/source" synology-downloadstation-bt-fix-9.9.9
  printf 'daemon\n' >"$SANDBOX/daemon"
  python3 -c '
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest() + "  daemon")
' "$SANDBOX/daemon" >"$SANDBOX/daemon.sha256"
  cat >"$SANDBOX/bin/curl" <<STUB
#!/bin/sh
out=""
url=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o)
      out="\$2"
      shift 2
      ;;
    *)
      url="\$1"
      shift
      ;;
  esac
done
case "\$url" in
  *.tar.gz) cp -f "$SANDBOX/source.tar.gz" "\$out" ;;
  *.sha256) cp -f "$SANDBOX/daemon.sha256" "\$out" ;;
  *) cp -f "$SANDBOX/daemon" "\$out" ;;
esac
STUB
  chmod 755 "$SANDBOX/bin/curl"
  PATH="$SANDBOX/bin:$PATH"
  export PATH
}

fresh_workdir() {
  WORKDIR="$SANDBOX/work-$1"
  mkdir -p "$WORKDIR"
}

test_fetch_scripts_returns_only_the_scripts_directory() {
  # Arrange
  fresh_workdir scripts

  # Act
  found=$(fetch_scripts "$TAG" 2>/dev/null)

  # Assert
  [ "$found" = "$WORKDIR/synology-downloadstation-bt-fix-9.9.9/scripts" ] ||
    fail "fetch_scripts returned [$found]"
  pass "fetch_scripts returns only the scripts directory"
}

test_fetch_and_verify_returns_only_the_daemon_path() {
  # Arrange
  fresh_workdir daemon

  # Act
  found=$(fetch_and_verify "$ARCH" "$TAG" 2>/dev/null)

  # Assert
  [ "$found" = "$WORKDIR/transmissiond-4.1.1-dsfix-$ARCH" ] ||
    fail "fetch_and_verify returned [$found]"
  pass "fetch_and_verify returns only the daemon path"
}

test_progress_still_reaches_the_terminal() {
  # Arrange
  fresh_workdir progress

  # Act
  progress=$(fetch_scripts "$TAG" 2>&1 >/dev/null)

  # Assert
  [ "$progress" = "fetching the installer scripts for $TAG" ] ||
    fail "fetch_scripts progress was [$progress]"
  pass "progress still reaches the terminal"
}

load_bootstrap_functions
make_fixtures
test_fetch_scripts_returns_only_the_scripts_directory
test_fetch_and_verify_returns_only_the_daemon_path
test_progress_still_reaches_the_terminal
