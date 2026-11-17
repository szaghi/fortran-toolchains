#!/usr/bin/env bash
# install.yml's interface-2 path locally (fortran-toolchains#3): tests/fixture-deps' release tarball (its dependency
# bundled by scripts/release-tarball.sh) installed through its one-line installer (FoBiS#217) with every build system it
# ships, by scripts/install-check.sh, in a fresh ubuntu:24.04 set up by setup/linux-bare.sh as install.yml's runner is.
# Needs docker, the network (the linux-bare toolchain's release, FoBiS's bootstrap, fpm's dependency) and fobis (or
# python3) for the bundling. The toolchain: setup/linux-bare-gcc.env's pins, or LINUX_BARE_GCC_TAG/_ASSET/_SHA256 and
# FORTRAN_TOOLCHAINS_GCC_URL (file:///path for a local build of tests/linux-bare-gcc.sh, mounted as is).
#
#   bash tests/install-check.sh [BUILD ...]        (default: fobis fpm cmake)
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
builds=${*:-fobis fpm cmake}
work=$(mktemp -d)
trap 'docker run --rm -v "$work:/w" alpine rm -rf /w/out /w/src > /dev/null 2>&1; rm -rf "$work"' EXIT

mkdir -p "$work/proj" "$work/src"
(cd "$here/tests/fixture-deps" && tar --exclude=./src/third_party -cf - .) | tar -xf - -C "$work/proj"
(cd "$work/proj" && bash "$here/scripts/release-tarball.sh" fixture_deps v1.0.0 "$work/out" --bundle) > "$work/tarball.log" 2>&1 \
  || { cat "$work/tarball.log"; exit 1; }
tar -xzf "$work/out/fixture_deps-v1.0.0.tar.gz" -C "$work/src"

# the linux-bare toolchain: setup/linux-bare-gcc.env's pins, or these variables (a local build served by file://)
gccdir=(); case ${FORTRAN_TOOLCHAINS_GCC_URL:-} in file://*) gccdir=(-v "${FORTRAN_TOOLCHAINS_GCC_URL#file://}:${FORTRAN_TOOLCHAINS_GCC_URL#file://}:ro") ;; esac
docker run --rm -v "$here:/ft:ro" -v "$work/src:/src:ro" -e BUILDS="$builds" "${gccdir[@]}" \
  -e LINUX_BARE_GCC_TAG -e LINUX_BARE_GCC_ASSET -e LINUX_BARE_GCC_SHA256 -e FORTRAN_TOOLCHAINS_GCC_URL ubuntu:24.04 bash -c '
  set -uo pipefail
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq > /dev/null && apt-get install -y -qq --no-install-recommends ca-certificates curl git > /dev/null
  eval "$(/ft/setup/linux-bare.sh repo | grep -v "^#")" > /dev/null
  eval "$(/ft/setup/linux-bare.sh install | grep "^export")"
  echo "toolchain: FC=$FC $($FC -dumpfullversion); fobis $(command -v fobis); pkg-config $(command -v pkg-config)"
  fails=0
  for b in $BUILDS; do
    /ft/scripts/install-check.sh /src/fixture_deps-v1.0.0/scripts/install.sh "$b" "/tmp/prefix-$b" \
      --source /src/fixture_deps-v1.0.0 --fc "$FC" > "/tmp/$b.log" 2>&1
    s=$?; grep -E "^(ok|::error|fixture_deps)|installed in" "/tmp/$b.log"; echo "== $b: exit $s"
    [ "$s" = 0 ] || { tail -25 "/tmp/$b.log"; fails=1; }
  done
  exit $fails'
s=$?
echo "install-check: exit $s"
exit $s
