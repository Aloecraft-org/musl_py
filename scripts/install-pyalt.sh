#!/bin/sh
#
# Install a musl_py release onto an Alpine host.
#
# Replaces the old "rsync the tarballs up and run the README by hand" flow:
#
#   wget -qO- https://github.com/Aloecraft-org/musl_py/releases/latest/download/install-pyalt.sh | sh
#
# or, pinned to a release (recommended for anything you care about):
#
#   wget -qO install.sh https://github.com/Aloecraft-org/musl_py/releases/download/v3.12.12-1/install-pyalt.sh
#   sh install.sh -r v3.12.12-1
#
# POSIX sh on purpose -- a minimal Alpine box has busybox ash, not bash.
set -eu

REPO="${MUSL_PY_REPO:-Aloecraft-org/musl_py}"
RELEASE="${MUSL_PY_RELEASE:-latest}"
PY_SERIES="${MUSL_PY_SERIES:-3.12}"
PREFIX="${MUSL_PY_PREFIX:-/usr/local}"
WHEELHOUSE="${MUSL_PY_WHEELHOUSE:-/opt/wheelhouse}"

usage() {
	cat <<EOF
usage: install-pyalt.sh [-r RELEASE] [-s SERIES] [-n]

  -r RELEASE  release tag to install (default: latest)
  -s SERIES   python series (default: $PY_SERIES)
  -n          download and verify only, do not install
EOF
}

DRY_RUN=0
while getopts "r:s:nh" opt; do
	case "$opt" in
		r) RELEASE="$OPTARG" ;;
		s) PY_SERIES="$OPTARG" ;;
		n) DRY_RUN=1 ;;
		h) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
	echo "error: must run as root (installs into $PREFIX and $WHEELHOUSE)" >&2
	exit 1
fi

if [ "$RELEASE" = "latest" ]; then
	BASE="https://github.com/$REPO/releases/latest/download"
else
	BASE="https://github.com/$REPO/releases/download/$RELEASE"
fi

fetch() { # url dest
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$2" "$1"
	else
		wget -q -O "$2" "$1"
	fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

PYALT="pyalt-$PY_SERIES.tar.gz"
WHEELS="wheelhouse-$PY_SERIES.tar.gz"

echo "==> fetching $RELEASE from $REPO"
for f in "$PYALT" "$WHEELS" SHA256SUMS; do
	fetch "$BASE/$f" "$TMP/$f"
done

echo "==> verifying checksums"
# SHA256SUMS covers assets we did not download; check only what we fetched.
grep -E "  ($PYALT|$WHEELS)\$" "$TMP/SHA256SUMS" > "$TMP/SHA256SUMS.want" || true
if [ "$(wc -l < "$TMP/SHA256SUMS.want")" -ne 2 ]; then
	echo "error: SHA256SUMS has no entries for $PYALT / $WHEELS" >&2
	exit 1
fi
( cd "$TMP" && sha256sum -c SHA256SUMS.want )

if [ "$DRY_RUN" -eq 1 ]; then
	echo "==> verified, not installing (-n)"
	exit 0
fi

echo "==> installing runtime libraries"
apk add --no-cache sqlite-libs libffi readline ncurses-libs xz-libs libbz2 zlib fuse3

echo "==> unpacking runtime into $PREFIX/pyalt"
tar xzf "$TMP/$PYALT" -C "$PREFIX"

echo "==> unpacking wheelhouse into $WHEELHOUSE"
mkdir -p "$WHEELHOUSE"
tar xzf "$TMP/$WHEELS" -C "$WHEELHOUSE"

PY="$PREFIX/pyalt/bin/python$PY_SERIES"

echo "==> installing packages (offline, from $WHEELHOUSE)"
"$PY" -m pip install --no-index \
	--find-links="$WHEELHOUSE" \
	-r "$WHEELHOUSE/requirements.txt"

echo "==> linking into $PREFIX/bin"
# So services and cron entries do not have to hardcode the pyalt prefix.
ln -sf "$PREFIX/pyalt/bin/python$PY_SERIES" "$PREFIX/bin/python$PY_SERIES"
ln -sf "$PREFIX/pyalt/bin/python$PY_SERIES" "$PREFIX/bin/python3"
ln -sf "$PREFIX/pyalt/bin/python$PY_SERIES" "$PREFIX/bin/python"
ln -sf "$PREFIX/pyalt/bin/pip$PY_SERIES" "$PREFIX/bin/pip$PY_SERIES"
ln -sf "$PREFIX/pyalt/bin/pip$PY_SERIES" "$PREFIX/bin/pip3"
ln -sf "$PREFIX/pyalt/bin/pip$PY_SERIES" "$PREFIX/bin/pip"
if [ -x "$PREFIX/pyalt/bin/certbot" ]; then
	ln -sf "$PREFIX/pyalt/bin/certbot" "$PREFIX/bin/certbot"
fi

echo "==> precompiling bytecode"
"$PY" -m compileall -q "$PREFIX/pyalt/lib/python$PY_SERIES" || true

echo "==> smoke test"
"$PY" -c "import ssl, sqlite3, ctypes, lzma, bz2, zlib, pydantic, flask, pyfuse3, aloelite; print('pyalt OK')"

cat <<EOF

installed $RELEASE

  python   $PY  (also on PATH as python3 / python)
  wheels   $WHEELHOUSE

if non-mounting users must reach aloelite fuse mounts, run once:
  echo user_allow_other >> /etc/fuse.conf
EOF
