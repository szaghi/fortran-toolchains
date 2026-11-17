#!/usr/bin/env bash
# debs.yml locally: the linux-bare bundle built by setup/linux-bare.sh in a fresh ubuntu:24.04 (the one step that needs
# the ubuntu-toolchain-r/test PPA on Launchpad), then installed from it in another fresh ubuntu:24.04 where Launchpad
# resolves to 127.0.0.1: the toolchain must come from the bundle and compile. A bundle with a wrong sha256 must be
# refused (the fallback to the PPA then fails, Launchpad being unreachable). The bundle is served by file:// through
# FORTRAN_TOOLCHAINS_DEBS_URL, as debs.yml's check serves it from the release. Needs docker and the network.
#
#   bash tests/linux-bare-debs.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'docker run --rm -v "$work:/w" alpine rm -rf /w/out > /dev/null 2>&1; rm -rf "$work"' EXIT
mkdir -p "$work/out"
no_launchpad=(--add-host ppa.launchpadcontent.net:127.0.0.1 --add-host ppa.launchpad.net:127.0.0.1
              --add-host launchpad.net:127.0.0.1 --add-host api.launchpad.net:127.0.0.1)

echo "== the bundle"
docker run --rm -v "$here:/ft:ro" -v "$work/out:/out" ubuntu:24.04 bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq > /dev/null && apt-get install -y -qq --no-install-recommends ca-certificates curl > /dev/null
  /ft/setup/linux-bare.sh bundle /out/bundle' > "$work/bundle.log" 2>&1 || { cat "$work/bundle.log"; exit 1; }
grep -E "^bundle:|^# (tag|asset|sha256)=" "$work/bundle.log"
tag=$(sed -n 's/^# tag=//p' "$work/bundle.log")
asset=$(sed -n 's/^# asset=//p' "$work/bundle.log")
sha=$(sed -n 's/^# sha256=//p' "$work/bundle.log")
mkdir -p "$work/out/serve/$tag" && cp "$work/out/bundle/$asset" "$work/out/serve/$tag/"

install_from() {   # install_from <sha256>: repo + install from the served bundle, Launchpad unreachable
  docker run --rm "${no_launchpad[@]}" -v "$here:/ft:ro" -v "$work/out/serve:/debs:ro" \
    -e LINUX_BARE_DEBS_TAG="$tag" -e LINUX_BARE_DEBS_ASSET="$asset" -e LINUX_BARE_DEBS_SHA256="$1" \
    -e FORTRAN_TOOLCHAINS_DEBS_URL=file:///debs ubuntu:24.04 bash -c '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq > /dev/null && apt-get install -y -qq --no-install-recommends ca-certificates curl > /dev/null
    eval "$(/ft/setup/linux-bare.sh repo | grep -v "^#")"
    eval "$(/ft/setup/linux-bare.sh install | tee /dev/stderr | grep "^export")"
    printf "program p\nprint *, \"linux-bare gfortran ok\"\nend program\n" > /tmp/p.f90
    "$FC" /tmp/p.f90 -o /tmp/p && /tmp/p && "$FC" -dumpfullversion'
}

fails=0
echo "== installed from the bundle, Launchpad unreachable"
install_from "$sha" > "$work/good.log" 2>&1; s=$?
grep -E "compiler packages|gfortran ok|^[0-9]+\.[0-9]+" "$work/good.log"
if [ "$s" != 0 ] || ! grep -q "compiler packages: the bundle $tag" "$work/good.log"; then
  tail -20 "$work/good.log"; echo "FAIL: not installed from the bundle"; fails=1
fi
echo "== a wrong sha256: refused"
install_from 0000000000000000000000000000000000000000000000000000000000000000 > "$work/bad.log" 2>&1; s=$?
grep -E "does not match" "$work/bad.log"
if [ "$s" = 0 ] || ! grep -q "does not match its pinned sha256" "$work/bad.log"; then
  tail -20 "$work/bad.log"; echo "FAIL: a wrong bundle was not refused"; fails=1
fi
echo "linux-bare-debs: exit $fails"
exit $fails
