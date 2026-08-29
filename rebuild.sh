#!/usr/bin/env bash
#
# Local full rebuild: runtime + wheelhouse into .generated/, then verify.
#
# Identical to what CI runs on a tag (.github/workflows/release.yml), so a green
# run here means a green release. Publishing is CI's job -- push a tag:
#
#   git tag v3.12.12-1 && git push origin v3.12.12-1
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
./scripts/build.sh
./scripts/smoke-test.sh
