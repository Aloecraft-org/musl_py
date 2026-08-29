#!/usr/bin/env bash
#
# Build the pyalt runtime and its wheelhouse into .generated/.
#
# Works with podman (local default) or docker (CI). Everything the release
# pipeline ships is produced here, so local builds and CI builds are the same
# build.
#
# Env overrides:
#   CONTAINER_ENGINE   podman|docker      (default: whichever is installed)
#   ALPINE_VERSION     base image tag     (default: 3.15)
#   PYTHON_VERSION     full version       (default: 3.12.12)
#   SQLITE_VERSION     sqlite.org id      (default: 3460100 -> 3.46.1)
#   JOBS               make -j            (default: nproc)
#   SKIP_IMAGE_BUILD   set to 1 to reuse an already-built image
#
# Flags:
#   --image-only       build the toolchain image and stop
set -euo pipefail

IMAGE_ONLY=0
for arg in "$@"; do
	case "$arg" in
		--image-only) IMAGE_ONLY=1 ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) echo "error: unknown argument: $arg" >&2; exit 2 ;;
	esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export ALPINE_VERSION="${ALPINE_VERSION:-3.15}"
export PYTHON_VERSION="${PYTHON_VERSION:-3.12.12}"
export SQLITE_VERSION="${SQLITE_VERSION:-3460100}"
# 3.12.12 -> 3.12; every path and artifact name derives from this.
export PY_SERIES="${PY_SERIES:-${PYTHON_VERSION%.*}}"
export JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

IMAGE="${IMAGE:-musl_py}"
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

# Rootless podman already maps container root to the invoking user. Docker does
# not, so hand it a uid:gid to chown build output back to -- otherwise the
# tarballs and 'make clean' need root on the host.
export CHOWN_TO=""
if [ "$ENGINE" = "docker" ]; then
	CHOWN_TO="$(id -u):$(id -g)"
fi

echo "==> engine=$ENGINE alpine=$ALPINE_VERSION python=$PYTHON_VERSION sqlite=$SQLITE_VERSION jobs=$JOBS"

if [ "${SKIP_IMAGE_BUILD:-0}" != "1" ]; then
	echo "==> building $IMAGE image"
	"$ENGINE" build \
		--build-arg "ALPINE_VERSION=$ALPINE_VERSION" \
		--build-arg "PYTHON_VERSION=$PYTHON_VERSION" \
		--build-arg "SQLITE_VERSION=$SQLITE_VERSION" \
		-t "$IMAGE" .
fi

if [ "$IMAGE_ONLY" = "1" ]; then
	echo "==> --image-only: stopping after image build"
	exit 0
fi

rm -rf pybuild wheels "$OUT_DIR"
mkdir -p pybuild wheels "$OUT_DIR"
chmod 777 pybuild wheels "$OUT_DIR"

# ---------------------------------------------------------------------------
# 1. sqlite + python into pybuild/
#
# sqlite is installed twice on purpose: once into the image's real prefix so
# Python's configure can find and link it, once into /out for packaging.
# ---------------------------------------------------------------------------
echo "==> building python $PYTHON_VERSION (this is the slow one -- PGO)"
"$ENGINE" run --rm \
	-v "$PWD/pybuild:/out" \
	-e PY_SERIES -e JOBS -e CHOWN_TO \
	"$IMAGE" sh -c '
		set -eu
		cd /opt/sqlite
		./configure --prefix=/usr/local/pyalt --disable-static
		make -j"$JOBS"
		make install
		make install DESTDIR=/out

		cd /opt/python
		CPPFLAGS="-I/usr/local/pyalt/include" \
		LDFLAGS="-L/usr/local/pyalt/lib -Wl,-rpath,/usr/local/pyalt/lib" \
		./configure --prefix=/usr/local/pyalt --enable-optimizations --with-ensurepip=install
		make -j"$JOBS"
		make altinstall DESTDIR=/out

		rm -rf "/out/usr/local/pyalt/lib/python$PY_SERIES/test" \
		       "/out/usr/local/pyalt/lib/python$PY_SERIES/idlelib" \
		       "/out/usr/local/pyalt/lib/python$PY_SERIES/turtledemo"
		strip "/out/usr/local/pyalt/bin/python$PY_SERIES" || true

		if [ -n "${CHOWN_TO:-}" ]; then chown -R "$CHOWN_TO" /out; fi
	'

# Packaged before anything runs pip against this tree, so the console-script
# shebangs still point at the real /usr/local/pyalt prefix.
tar czf "$OUT_DIR/pyalt-$PY_SERIES.tar.gz" \
	--owner=0 --group=0 --numeric-owner \
	-C pybuild/usr/local pyalt
echo "==> wrote $OUT_DIR/pyalt-$PY_SERIES.tar.gz"

# ---------------------------------------------------------------------------
# 2. wheels
#
# The runtime tarball is unpacked at its real path rather than bind-mounting
# pybuild/ at /pyroot. Two reasons: pip rewrites console-script shebangs to
# whatever prefix it is run from (the old /pyroot sed hack), and building the
# wheels against the actual release artifact proves the two ship together.
# ---------------------------------------------------------------------------
echo "==> building wheels"
"$ENGINE" run --rm \
	-v "$PWD/$OUT_DIR:/generated:ro" \
	-v "$PWD/wheels:/wheels" \
	-v "$PWD/requirements.txt:/requirements.txt:ro" \
	-e PY_SERIES -e CHOWN_TO \
	"$IMAGE" sh -c '
		set -eu
		apk add --no-cache fuse3-dev pkgconf linux-headers
		tar xzf "/generated/pyalt-$PY_SERIES.tar.gz" -C /usr/local

		PY="/usr/local/pyalt/bin/python$PY_SERIES"
		"$PY" -m pip install --upgrade pip wheel
		"$PY" -m pip wheel --wheel-dir=/wheels -r /requirements.txt

		# Ship the list alongside the wheels so the installer never has to
		# guess what this wheelhouse was built to satisfy.
		cp /requirements.txt /wheels/requirements.txt

		if [ -n "${CHOWN_TO:-}" ]; then chown -R "$CHOWN_TO" /wheels; fi
	'

tar czf "$OUT_DIR/wheelhouse-$PY_SERIES.tar.gz" \
	--owner=0 --group=0 --numeric-owner \
	-C wheels .
echo "==> wrote $OUT_DIR/wheelhouse-$PY_SERIES.tar.gz"

# ---------------------------------------------------------------------------
# 3. manifest + checksums
# ---------------------------------------------------------------------------
cp requirements.txt "$OUT_DIR/requirements.txt"
cp scripts/install-pyalt.sh "$OUT_DIR/install-pyalt.sh"

{
	echo "musl_py build manifest"
	echo
	echo "built     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "commit    $(git rev-parse HEAD 2>/dev/null || echo unknown)"
	echo "platform  linux/$(uname -m), musl (alpine $ALPINE_VERSION)"
	echo "python    $PYTHON_VERSION"
	echo "sqlite    $SQLITE_VERSION"
	echo
	echo "wheelhouse"
	find wheels -maxdepth 1 -name '*.whl' -exec basename {} \; | sort | sed 's/^/  /'
} > "$OUT_DIR/MANIFEST.txt"

( cd "$OUT_DIR" && sha256sum \
	"pyalt-$PY_SERIES.tar.gz" \
	"wheelhouse-$PY_SERIES.tar.gz" \
	requirements.txt install-pyalt.sh > SHA256SUMS )

echo
echo "==> $OUT_DIR:"
ls -lh "$OUT_DIR"
