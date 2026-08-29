# Local builds. Releases are published by .github/workflows/release.yml on tag push.
.PHONY: all image build smoke clean

all: build smoke

## build the alpine toolchain image only
image:
	./scripts/build.sh --image-only

## runtime + wheelhouse into .generated/
build:
	./scripts/build.sh

## verify .generated/ by installing it onto a clean alpine container
smoke:
	./scripts/smoke-test.sh

clean:
	rm -rf pybuild wheels .generated
