#!/usr/bin/env bash
#
# Verify the artifacts in .generated/ by performing the real VPS install into a
# clean alpine container: unpack, install every wheel offline, import everything.
#
# --no-index is the important part -- it fails if the wheelhouse is missing a
# transitive dependency, which is the failure that otherwise only shows up on
# the VPS after the tarballs have already shipped.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ALPINE_VERSION="${ALPINE_VERSION:-3.15}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12.12}"
export PY_SERIES="${PY_SERIES:-${PYTHON_VERSION%.*}}"
OUT_DIR="${OUT_DIR:-.generated}"

if [ -n "${CONTAINER_ENGINE:-}" ]; then
	ENGINE="$CONTAINER_ENGINE"
elif command -v podman >/dev/null 2>&1; then
	ENGINE=podman
elif command -v docker >/dev/null 2>&1; then
	ENGINE=docker
else
	echo "error: no container engine found (need podman or docker)" >&2
	exit 1
fi

for f in "pyalt-$PY_SERIES.tar.gz" "wheelhouse-$PY_SERIES.tar.gz"; do
	if [ ! -f "$OUT_DIR/$f" ]; then
		echo "error: $OUT_DIR/$f missing -- run scripts/build.sh first" >&2
		exit 1
	fi
done

echo "==> smoke testing $OUT_DIR on a clean alpine:$ALPINE_VERSION"
"$ENGINE" run --rm \
	-v "$PWD/$OUT_DIR:/generated:ro" \
	-e PY_SERIES \
	"alpine:$ALPINE_VERSION" sh -c '
		set -eu
		apk add --no-cache sqlite-libs libffi readline ncurses-libs xz-libs bzip2 zlib fuse3

		tar xzf "/generated/pyalt-$PY_SERIES.tar.gz" -C /usr/local
		mkdir -p /opt/wheelhouse
		tar xzf "/generated/wheelhouse-$PY_SERIES.tar.gz" -C /opt/wheelhouse

		PY="/usr/local/pyalt/bin/python$PY_SERIES"
		"$PY" -m pip install --no-index \
			--find-links=/opt/wheelhouse \
			-r /opt/wheelhouse/requirements.txt

		"$PY" - <<"PYEOF"
import ssl, sqlite3, ctypes, lzma, bz2, zlib, readline
import pydantic, flask, yaml, cron_converter, certbot, pyfuse3, aloelite

print("python  ", __import__("sys").version.replace("\n", " "))
print("openssl ", ssl.OPENSSL_VERSION)
print("sqlite  ", sqlite3.sqlite_version)
print("pydantic", pydantic.VERSION)

# Alpine 3.15 ships sqlite 3.36; anything that old means the bundled build did
# not take and the rpath fell through to the system library.
assert sqlite3.sqlite_version_info >= (3, 40), (
    f"linked against system sqlite {sqlite3.sqlite_version}, not the bundled one"
)
print("pyalt OK")
PYEOF

		# console scripts must be runnable, with a shebang pointing at the real
		# prefix rather than a build-time bind-mount path.
		head -1 /usr/local/pyalt/bin/pip$PY_SERIES
		/usr/local/pyalt/bin/certbot --version
	'

echo "==> smoke test passed"
