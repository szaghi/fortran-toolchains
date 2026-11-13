#!/usr/bin/env bash
# Tests of check-versions.sh with stub tools on PATH (no real toolchain needed). Portable to bash 3.2: run it with the
# shell to test, e.g. `bash common/test-check-versions.sh` and, for macOS's bash,
# `docker run --rm -v "$PWD:/r" -w /r bash:3.2 bash common/test-check-versions.sh`.
set -u
here=$(cd "$(dirname "$0")" && pwd)
cv="$here/check-versions.sh"
stubs=$(mktemp -d 2>/dev/null || mktemp -d -t stubs)
trap 'rm -rf "$stubs"' EXIT
printf '#!/bin/sh\necho "Version:     0.13.0, alpha"\n' > "$stubs/fpm"
printf '#!/bin/sh\necho "cmake version 4.4.5"\n' > "$stubs/cmake"
printf '#!/bin/sh\necho "1.13.2.git.kitware.jobserver-pipe-1"\n' > "$stubs/ninja"
printf '#!/bin/sh\necho "16.2.0"\n' > "$stubs/gfortran-16"
printf '#!/bin/sh\nexit 127\n' > "$stubs/node"   # a tool that is not there
chmod +x "$stubs"/*
printf 'FPM=0.13.0\nCMAKE=4.4.4\nNINJA=1.13.2\nGCC=16.2.0\nNODE=24.13.0\n' > "$stubs/versions.env"

pass=0 failed=0
expect() {   # expect <exit status> <grep pattern of the output|-> <command...>
  local want=$1 pattern=$2; shift 2
  local out rc
  out=$(PATH="$stubs:$PATH" "$@" 2>&1); rc=$?
  if [ "$rc" = "$want" ] && { [ "$pattern" = - ] || printf '%s\n' "$out" | grep -qE "$pattern"; }; then
    pass=$((pass + 1))
  else
    failed=$((failed + 1)); printf 'FAILED: %s (exit %s, wanted %s)\n%s\n' "$*" "$rc" "$want" "$out"
  fi
}

expect 0 '^FPM +0\.13\.0 +ok$'                  env FPM=0.13.0 "$BASH" "$cv" FPM
expect 0 '^NINJA +1\.13\.2 +ok$'                env NINJA=1.13.2 "$BASH" "$cv" NINJA
expect 1 'MISMATCH \(found 4\.4\.5\)'           env CMAKE=4.4.4 "$BASH" "$cv" CMAKE
expect 0 '::warning title=version drift::CMAKE' env CMAKE=4.4.4 "$BASH" "$cv" --policy major CMAKE
expect 1 '::error title=version drift::CMAKE'   env CMAKE=3.31.6 "$BASH" "$cv" --policy major CMAKE
expect 1 'no pin for FPM'                       env -u FPM "$BASH" "$cv" FPM
expect 1 'MISSING'                              env NODE=24.13.0 "$BASH" "$cv" NODE
expect 0 '^GCC +16\.2\.0 +ok$'                  env FC=gfortran-16 "$BASH" "$cv" --pins "$stubs/versions.env" GCC
expect 0 '^FPM +0\.13\.0 +ok$'                  "$BASH" "$cv" --pins "$stubs/versions.env" FPM
expect 0 'DRIFT \(found 4\.4\.5, same major\)'  "$BASH" "$cv" --pins "$stubs/versions.env" --policy major CMAKE
expect 1 'MISMATCH'                             "$BASH" "$cv" --pins "$stubs/versions.env" CMAKE
expect 2 'unknown policy'                       "$BASH" "$cv" --policy loose FPM

echo "check-versions.sh: $pass passed, $failed failed (bash $BASH_VERSION)"
[ "$failed" = 0 ]
