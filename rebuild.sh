#! /bin/bash


# TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
# echo $TIMESTAMP

# IMAGE_NAME=musl_py
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# mkdir -p ${SCRIPT_DIR}/.build/pybuild ${SCRIPT_DIR}/.build/wheels

# podman build -t $IMAGE_NAME ${SCRIPT_DIR}

rm -rf pybuild
rm -rf wheels
rm -rf .generated

mkdir -p pybuild
chmod 777 pybuild
mkdir -p wheels
chmod 777 wheels
mkdir -p .generated
chmod 777 .generated

podman build -t musl_py .

podman run --rm -v $(pwd)/pybuild:/out musl_py sh -c '
	cd /opt/sqlite
	./configure --prefix=/usr/local/pyalt --disable-static
	make -j$(nproc) && make install && make install DESTDIR=/out
	cd /opt/python
	CPPFLAGS="-I/usr/local/pyalt/include" \
	LDFLAGS="-L/usr/local/pyalt/lib -Wl,-rpath,/usr/local/pyalt/lib" \
	./configure --prefix=/usr/local/pyalt --enable-optimizations --with-ensurepip=install
	make -j$(nproc) && make altinstall DESTDIR=/out
	rm -rf /out/usr/local/pyalt/lib/python3.12/test \
		/out/usr/local/pyalt/lib/python3.12/idlelib \
		/out/usr/local/pyalt/lib/python3.12/turtledemo
	strip /out/usr/local/pyalt/bin/python3.12 || true
'

tar czf pyalt-3.12.tar.gz -C pybuild/usr/local pyalt
mv pyalt-3.12.tar.gz .generated

podman run --rm \
    -v $(pwd)/pybuild:/pyroot \
    -v $(pwd)/wheels:/wheels \
    musl_py sh -c '
        apk add --no-cache fuse3-dev pkgconf linux-headers
        /pyroot/usr/local/pyalt/bin/python3.12 -m pip install --upgrade pip wheel
        /pyroot/usr/local/pyalt/bin/python3.12 -m pip wheel --wheel-dir=/wheels pydantic flask cron-converter pyyaml certbot "aloelite[fuse]==0.3.5"
'

tar czf wheelhouse-3.12.tar.gz -C wheels .
mv wheelhouse-3.12.tar.gz .generated