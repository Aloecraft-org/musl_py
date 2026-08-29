## Goal: Python 3.12 + Pydantic on Alpine 3.15 (EOL; OpenSSL 1.1.1 caps us below Python 3.14)

The goal is to prebuild python on pydantic on my local machine for Alpine 3.15 to take that specific burden off of the lightweight Dartnode VPS-1 VPS

## Build Alpine Container

``` sh
podman build -t musl_py .
```

	<!-- @podman run --rm -v $(pwd)/pybuild:/out musl_py sh -c '
		cd /opt/python
		./configure --prefix=/usr --enable-optimizations --with-ensurepip=install
		make -j$(nproc) && make altinstall DESTDIR=/out'	 -->


## Build Python
``` sh
mkdir -p pybuild
chmod 777 pybuild
mkdir -p .generated

podman run --rm -v $(pwd)/pybuild:/out musl_py sh -c '
    cd /opt/python
    ./configure --prefix=/usr/local/pyalt --enable-optimizations --with-ensurepip=install
    make -j$(nproc) && make altinstall DESTDIR=/out
    rm -rf /out/usr/local/pyalt/lib/python3.12/test \
           /out/usr/local/pyalt/lib/python3.12/idlelib \
           /out/usr/local/pyalt/lib/python3.12/turtledemo
    strip /out/usr/local/pyalt/bin/python3.12 || true'

tar czf pyalt-3.12.tar.gz -C pybuild/usr/local pyalt
mv pyalt-3.12.tar.gz .generated
```

## Build pip dependencies
``` sh
mkdir -p wheels
chmod 777 wheels
mkdir -p .generated

podman run --rm \
  -v $(pwd)/pybuild:/pyroot \
  -v $(pwd)/wheels:/wheels \
  musl_py sh -c '
    apk add --no-cache fuse3-dev pkgconf linux-headers
    /pyroot/usr/local/pyalt/bin/python3.12 -m pip install --upgrade pip wheel
    # /pyroot/usr/local/pyalt/bin/python3.12 -m pip wheel --wheel-dir=/wheels -r /wheels/requirements.txt
    /pyroot/usr/local/pyalt/bin/python3.12 -m pip wheel --wheel-dir=/wheels pydantic flask cron-converter pyyaml certbot "aloelite[fuse]"'

tar czf wheelhouse-3.12.tar.gz -C wheels .
mv wheelhouse-3.12.tar.gz .generated
```

## rsync to vps
``` sh
rsync -rlptv pyalt-3.12.tar.gz wheelhouse-3.12.tar.gz dart2:/opt/
```

## On the VPS (once)
``` sh
# apk add --no-cache sqlite-libs libffi readline ncurses-libs xz-libs bzip2 zlib <-- already added
apk add --no-cache fuse3
echo "user_allow_other" >> /etc/fuse.conf   # only if non-mounting users must access mounts

tar xzf /opt/pyalt-3.12.tar.gz -C /usr/local
mkdir -p /opt/wheelhouse
tar xzf /opt/wheelhouse-3.12.tar.gz -C /opt/wheelhouse
/usr/local/pyalt/bin/python3.12 -m pip install --no-index \
    --find-links=/opt/wheelhouse pydantic flask cron-converter pyyaml certbot "aloelite[fuse]"

sed -i "1s|/pyroot||" /pyroot/usr/local/pyalt/bin/pip* /pyroot/usr/local/pyalt/bin/wheel

# Expose on PATH so services/cron don't hardcode the prefix
ln -sf /usr/local/pyalt/bin/python3.12 /usr/local/bin/python3.12
ln -sf /usr/local/pyalt/bin/python3.12 /usr/local/bin/python3
ln -sf /usr/local/pyalt/bin/python3.12 /usr/local/bin/python
ln -sf /usr/local/pyalt/bin/pip3.12    /usr/local/bin/pip3.12
ln -sf /usr/local/pyalt/bin/pip3.12    /usr/local/bin/pip3
ln -sf /usr/local/pyalt/bin/pip3.12    /usr/local/bin/pip
ln -sf /usr/local/pyalt/bin/certbot    /usr/local/bin/certbot

# Precompile bytecode (faster cold starts, avoids root-owned pycache surprises later)
/usr/local/pyalt/bin/python3.12 -m compileall -q /usr/local/pyalt/lib/python3.12

# Smoke test: fails loudly if a runtime lib or wheel is missing
/usr/local/pyalt/bin/python3.12 -c "import ssl, sqlite3, ctypes, lzma, bz2, zlib, pydantic, flask, pyfuse3, aloelite; print('pyalt OK')"

# TODO: point renewal cron at /usr/local/bin/certbot
```
