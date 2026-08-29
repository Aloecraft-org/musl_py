# musl_py

Prebuilt CPython 3.12 + an offline wheelhouse for **Alpine 3.15**, so the
lightweight Dartnode VPS-1 never has to compile any of it.

Alpine 3.15 is EOL and ships OpenSSL 1.1.1, which caps us below Python 3.14, so
3.12 it is. SQLite is built from source alongside it — Alpine 3.15's is 3.36,
too old for modern `sqlite3` usage.

Releases are built and published by GitHub Actions. Nothing needs to be built or
copied by hand any more.

## Using a release

On the Alpine host:

```sh
wget -qO install-pyalt.sh https://github.com/Aloecraft-org/musl_py/releases/latest/download/install-pyalt.sh
sh install-pyalt.sh
```

That downloads the runtime and wheelhouse, verifies their checksums, installs
the runtime deps, unpacks to `/usr/local/pyalt` and `/opt/wheelhouse`, installs
every package offline, links `python3`/`pip3`/`certbot` onto `PATH`, precompiles
bytecode and smoke tests the result.

Pin the release for anything you care about — `latest` moves:

```sh
sh install-pyalt.sh -r v3.12.12-1
```

`-n` downloads and verifies without installing. `MUSL_PY_PREFIX` and
`MUSL_PY_WHEELHOUSE` override the install locations.

### Fetching the tarballs directly

If a project would rather drive the install itself:

```sh
base=https://github.com/Aloecraft-org/musl_py/releases/latest/download
wget -q "$base/pyalt-3.12.tar.gz" "$base/wheelhouse-3.12.tar.gz" "$base/SHA256SUMS"
sha256sum -c --ignore-missing SHA256SUMS

tar xzf pyalt-3.12.tar.gz -C /usr/local
mkdir -p /opt/wheelhouse && tar xzf wheelhouse-3.12.tar.gz -C /opt/wheelhouse
/usr/local/pyalt/bin/python3.12 -m pip install --no-index \
    --find-links=/opt/wheelhouse -r /opt/wheelhouse/requirements.txt
```

The repo is public, so none of this needs a token.

## Cutting a release

Push a tag:

```sh
git tag v3.12.12-1
git push origin v3.12.12-1
```

`.github/workflows/release.yml` then builds the runtime and wheelhouse, verifies
them on a clean `alpine:3.15` container, and publishes a release with the
tarballs, `requirements.txt`, `install-pyalt.sh`, `MANIFEST.txt` and
`SHA256SUMS`.

Tags are just labels — `v<python version>-<build number>` is the convention, but
nothing parses them. Bump the build number when the package set changes and the
Python version does not.

To rehearse without publishing, run the workflow from the Actions tab with
**tag** left blank: it builds and verifies, and attaches the artifacts to the
run instead of creating a release. Filling **tag** in publishes from the UI
without touching git.

The build takes roughly 45–75 minutes, most of it PGO.

## Building locally

Needs podman or docker.

```sh
./rebuild.sh      # build + verify, output in .generated/
```

or

```sh
make build        # runtime + wheelhouse into .generated/
make smoke        # install .generated/ onto a clean container and import everything
make image        # toolchain image only
make clean
```

`rebuild.sh` and CI both call `scripts/build.sh`, so a green local run means a
green release. Engine is auto-detected; override with `CONTAINER_ENGINE=docker`.

## What a release contains

| Asset | |
|---|---|
| `pyalt-3.12.tar.gz` | the runtime, unpacks to `pyalt/` (intended for `/usr/local`) |
| `wheelhouse-3.12.tar.gz` | every wheel from `requirements.txt` plus a copy of that file |
| `requirements.txt` | what the wheelhouse was built to satisfy |
| `install-pyalt.sh` | the installer above |
| `MANIFEST.txt` | alpine/python/sqlite versions, commit, and every resolved wheel version |
| `SHA256SUMS` | checksums for all of the above |

Built for **x86_64 musl** only. Adding arm64 means a second matrix entry on an
`ubuntu-24.04-arm` runner and arch-suffixed asset names.

## Changing what gets built

- **Packages** — edit `requirements.txt`. It is the only list; the build, the
  smoke test and the installer all read it.
- **Python, SQLite or Alpine version** — the defaults live at the top of
  `scripts/build.sh` and are passed through to the Dockerfile as build args.
  Every path and artifact name derives from `PYTHON_VERSION`, so a series bump
  is a one-line change.

## VPS notes

The installer handles everything mechanical. Two things it deliberately leaves
alone:

```sh
# only if non-mounting users must reach aloelite fuse mounts
echo user_allow_other >> /etc/fuse.conf
```

TODO: point the renewal cron at `/usr/local/bin/certbot`.
