#!/usr/bin/env bash
# The project's pipeline on any toolchain (fortran-toolchains' matrix workflow runs it with the environment contract:
# FC, CC, CXX, TOOLCHAIN, TOOLCHAIN_OS, TOOLCHAIN_FAMILY): build the tests with the fobos mode of the toolchain's
# family, run them; with fpm too. The same script runs on WSL, in `docker run <image>` and in CI.
set -euo pipefail
echo "toolchain: $TOOLCHAIN ($TOOLCHAIN_OS, $TOOLCHAIN_FAMILY), FC=$FC"
fobis build --mode "tests-$TOOLCHAIN_FAMILY"
bash scripts/run_tests.sh
fpm test --compiler "$FC" --c-compiler "$CC"
