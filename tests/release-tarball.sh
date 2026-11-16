#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # the checks are eval'ed strings reading the variables set below
# scripts/release-tarball.sh on tests/fixture-deps (fortran-toolchains#3): the dependencies bundled (fetched from
# GitHub), never their .git; a hidden deps_dir bundled too; without --bundle nothing fetched; the bundled tarball builds
# with CMake in the gnu-16.2 image without a network. Needs fobis (or python3 for a venv), docker and the network.
#
#   bash tests/release-tarball.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'docker run --rm -v "$work:/w" alpine rm -rf /w/out /w/build > /dev/null 2>&1; rm -rf "$work"' EXIT
fails=0
check() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fails=$((fails + 1)); fi; }

checkout() { # a fresh checkout of the fixture: no fetched dependencies
  rm -rf "$work/proj"; mkdir -p "$work/proj"
  (cd "$here/tests/fixture-deps" && tar --exclude=./src/third_party --exclude=./.fobis_deps -cf - .) | tar -xf - -C "$work/proj"
}

# bundled into src/third_party (the fixture's deps_dir)
checkout
(cd "$work/proj" && bash "$here/scripts/release-tarball.sh" fixture_deps v1.0.0 "$work/out" --bundle \
  --excludes "build obj mod") > "$work/bundle.log" 2>&1; s=$?
check "bundle: the script succeeds" '[ $s = 0 ] && [ -f "$work/out/fixture_deps-v1.0.0.tar.gz" ]'
tar -tzf "$work/out/fixture_deps-v1.0.0.tar.gz" > "$work/list"
check "bundle: PENF's sources in the tarball" 'grep -q "^fixture_deps-v1.0.0/src/third_party/PENF/src/lib/penf.F90$" "$work/list"'
check "bundle: no .git directory" '! grep -q "/\.git/" "$work/list"'
check "bundle: every entry under fixture_deps-v1.0.0/" '! grep -vq "^fixture_deps-v1.0.0/" "$work/list"'
check "bundle: PENF and its commit listed" 'grep -Eq "^- PENF [0-9a-f]{40}$" "$work/bundle.log"'

# offline: the bundled tarball builds with CMake, no FoBiS, no network
mkdir -p "$work/build"
tar -xzf "$work/out/fixture_deps-v1.0.0.tar.gz" -C "$work/build"
docker run --rm --network none -v "$work/build:/w" -w /w/fixture_deps-v1.0.0 ghcr.io/szaghi/fortran-toolchains:gnu-16.2 \
  bash -c 'for f in $(command -v fobis FoBiS.py); do mv "$f" "$f.off"; done; ! command -v fobis > /dev/null &&
           cmake -S . -B /tmp/b > /tmp/c.log 2>&1 && cmake --build /tmp/b > /tmp/b.log 2>&1 && ls /tmp/b/libfixture_deps.a' \
  > "$work/offline.log" 2>&1; s=$?
check "offline: CMake builds the bundled tarball without FoBiS nor network" '[ $s = 0 ]'

# a hidden deps_dir (.fobis_deps): bundled by name, the glob would leave it out
checkout
sed -i 's|^deps_dir = src/third_party|deps_dir = .fobis_deps|' "$work/proj/fobos"
rm -rf "$work/out"
(cd "$work/proj" && bash "$here/scripts/release-tarball.sh" fixture_deps v1.0.0 "$work/out" --bundle) > "$work/hidden.log" 2>&1
tar -tzf "$work/out/fixture_deps-v1.0.0.tar.gz" > "$work/list"   # a file, not a pipe: grep -q would SIGPIPE tar
check "hidden deps_dir: bundled" 'grep -q "^fixture_deps-v1.0.0/.fobis_deps/PENF/src/lib/penf.F90$" "$work/list"'

# without --bundle: nothing fetched, nothing bundled
checkout
rm -rf "$work/out"
(cd "$work/proj" && bash "$here/scripts/release-tarball.sh" fixture_deps v1.0.0 "$work/out") > "$work/plain.log" 2>&1
tar -tzf "$work/out/fixture_deps-v1.0.0.tar.gz" > "$work/list"
check "no --bundle: no dependency in the tarball" '! grep -q third_party "$work/list"'

echo "release-tarball: $fails failure(s)"
[ "$fails" = 0 ]
