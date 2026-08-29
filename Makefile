clean:
	rm -rf pybuild
	rm -rf wheels
	rm -rf .generated

init:
	@mkdir -p pybuild
	@chmod 777 pybuild
	@mkdir -p wheels
	@chmod 777 wheels
	@mkdir -p .generated
	@chmod 777 .generated

build_container:
	podman build -t musl_py .

build:

	podman run --rm \
		-v $(pwd)/pybuild:/pyroot \
		-v $(pwd)/wheels:/wheels \
		musl_py sh -c '
			apk add --no-cache fuse3-dev pkgconf linux-headers
			/pyroot/usr/local/pyalt/bin/python3.12 -m pip install --upgrade pip wheel
			# /pyroot/usr/local/pyalt/bin/python3.12 -m pip wheel --wheel-dir=/wheels -r /wheels/requirements.txt
			/pyroot/usr/local/pyalt/bin/python3.12 -m pip wheel --wheel-dir=/wheels pydantic flask cron-converter pyyaml certbot "aloelite[fuse]"'