#!/usr/bin/env bash
# gcc.yml locally: the linux-bare compiler built by setup/linux-bare.sh from the GNU release (its signature and sha256
# checked against setup/linux-bare-gcc.env) in a fresh ubuntu:24.04, then installed from it in another fresh
# ubuntu:24.04 where Launchpad resolves to 127.0.0.1 (no PPA anywhere): gfortran at the exact pin compiles and runs a
# program, its runtime found through ldconfig. A toolchain with a wrong sha256, and no pin at all, must fail. The
# toolchain is served by file:// through FORTRAN_TOOLCHAINS_GCC_URL, as gcc.yml's check serves it from the release.
# Needs docker and the network (the GNU mirrors, Ubuntu's archive). The build takes about 20 minutes on 16 cores.
#
#   bash tests/linux-bare-gcc.sh [OUT]     (OUT keeps the built toolchain; default: a temporary directory)
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-}
work=$(mktemp -d)
[ -n "$out" ] || out=$work/out
mkdir -p "$out"
trap 'rm -rf "$work"' EXIT
gcc=$(sed -n 's/^GCC=//p' "$here/versions.env")
no_launchpad=(--add-host ppa.launchpadcontent.net:127.0.0.1 --add-host ppa.launchpad.net:127.0.0.1
              --add-host launchpad.net:127.0.0.1 --add-host api.launchpad.net:127.0.0.1)

if [ ! -f "$out/build.log" ] || ! grep -q "^# sha256=" "$out/build.log"; then
  echo "== the toolchain, built"
  docker run --rm -v "$here:/ft:ro" -v "$out:/out" ubuntu:24.04 bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq > /dev/null && apt-get install -y -qq --no-install-recommends ca-certificates curl > /dev/null
    /ft/setup/linux-bare.sh build /out/toolchain' > "$out/build.log" 2>&1 || { tail -40 "$out/build.log"; exit 1; }
fi
grep -E "^(source|toolchain):|^# (tag|asset|sha256)=" "$out/build.log"
tag=$(sed -n 's/^# tag=//p' "$out/build.log")
asset=$(sed -n 's/^# asset=//p' "$out/build.log")
sha=$(sed -n 's/^# sha256=//p' "$out/build.log")
mkdir -p "$out/serve/$tag" && cp "$out/toolchain/$asset" "$out/serve/$tag/"

install_from() {   # install_from <tag> <sha256>: repo + install from the served toolchain, Launchpad unreachable
  docker run --rm "${no_launchpad[@]}" -v "$here:/ft:ro" -v "$out/serve:/gcc:ro" \
    -e LINUX_BARE_GCC_TAG="$1" -e LINUX_BARE_GCC_ASSET="$asset" -e LINUX_BARE_GCC_SHA256="$2" \
    -e FORTRAN_TOOLCHAINS_GCC_URL=file:///gcc ubuntu:24.04 bash -c '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq > /dev/null && apt-get install -y -qq --no-install-recommends ca-certificates curl > /dev/null
    eval "$(/ft/setup/linux-bare.sh repo | grep -v "^#")"
    eval "$(/ft/setup/linux-bare.sh install | tee /dev/stderr | grep "^export")"
    if grep -rqs launchpad /etc/apt/sources.list /etc/apt/sources.list.d; then echo "a Launchpad source is configured"; exit 1; fi
    printf "program p\nuse iso_fortran_env, only: compiler_version\nprint *, \"linux-bare: \", compiler_version()\nend program\n" > /tmp/p.f90
    "$FC" /tmp/p.f90 -o /tmp/p && /tmp/p && echo "fullversion $("$FC" -dumpfullversion)"
    ldd /tmp/p | grep libgfortran'
}

fails=0
echo "== installed from the toolchain, Launchpad unreachable"
install_from "$tag" "$sha" > "$work/good.log" 2>&1; s=$?
grep -E "^compiler:|linux-bare: |fullversion|libgfortran" "$work/good.log"
if [ "$s" != 0 ] || ! grep -q "fullversion $gcc$" "$work/good.log" || ! grep -q "libgfortran.*/opt/gcc/bin/$gcc/" "$work/good.log"; then
  tail -20 "$work/good.log"; echo "FAIL: not the pinned toolchain, or its runtime not found"; fails=1
fi
echo "== a wrong sha256: refused"
install_from "$tag" 0000000000000000000000000000000000000000000000000000000000000000 > "$work/bad.log" 2>&1; s=$?
grep -E "does not match" "$work/bad.log"
if [ "$s" = 0 ] || ! grep -q "does not match its pinned sha256" "$work/bad.log"; then
  tail -20 "$work/bad.log"; echo "FAIL: a wrong toolchain was not refused"; fails=1
fi
echo "== no pin: an error, no fallback"
docker run --rm -v "$here:/ft:ro" ubuntu:24.04 bash -c 'apt-get update -qq > /dev/null; apt-get install -y -qq curl > /dev/null 2>&1; /ft/setup/linux-bare.sh install' > "$work/none.log" 2>&1; s=$?
grep -E "no toolchain pinned" "$work/none.log"
if [ "$s" = 0 ] || ! grep -q "no toolchain pinned" "$work/none.log"; then tail -10 "$work/none.log"; echo "FAIL: no pin did not fail"; fails=1; fi
echo "linux-bare-gcc: exit $fails"
exit $fails
