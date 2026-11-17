#!/usr/bin/env bash
# The linux-bare toolchain on a fresh Ubuntu runner, for the jobs that must test a fresh machine rather than an image
# (installers): gcc/g++/gfortran of the GCC pin's major from the ubuntu-toolchain-r/test PPA (the only gcc 16 for
# Ubuntu 24.04 is its snapshot, a same-major drift the checks warn about), CMake, ninja, fpm at their pins in /opt,
# FoBiS pinned in a venv. Root or sudo. Called by .github/actions/setup-linux-bare in two phases, the action
# restoring the cache of the compiler's packages between them (388 MB from the PPA for gcc 16, minutes to download):
#
#   linux-bare.sh repo       the base packages; the PPA added, unless the compiler's packages come from this
#                                  repository's bundle (setup/linux-bare-debs.env); prints the cache key as a step
#                                  output (gcc=: the bundle's tag, or the compiler's PPA version)
#   linux-bare.sh install    the compiler, from the bundle (downloaded once into $FORTRAN_TOOLCHAINS_HOME/debs, the
#                                  cached directory, and checked against its pinned sha256) or else from the PPA
#                                  (apt's archives in the same directory); the tools, unversioned links to the
#                                  compilers ahead of the runner's own; exports the contract
#   linux-bare.sh bundle DIR on a fresh Ubuntu: the PPA's packages of the compiler (those apt downloads that come from
#                                  the PPA, not Ubuntu's archive) as DIR/linux-bare-debs-<arch>.tar.xz, its .sha256 and
#                                  a manifest; prints the tag, the asset and the sha256 as outputs (debs.yml publishes
#                                  them)
#
# The bundle removes Launchpad from every job but the one that builds it: a fresh runner downloads the packages from
# this repository's release, and apt takes their Ubuntu dependencies from the runner's archive mirror.
#
# Writes to $GITHUB_ENV, $GITHUB_PATH and $GITHUB_OUTPUT inside a job; prints `export` lines otherwise.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
pins=$root/versions.env
pin() { sed -n "s/^$1=//p" "$pins"; }
sudo=; [ "$(id -u)" = 0 ] || sudo=sudo
home=${FORTRAN_TOOLCHAINS_HOME:-$HOME/.fortran-toolchains}
# the bundle's pins: the environment, else setup/linux-bare-debs.env
debpin() { local v; v=$(printenv "$1" || true); [ -n "$v" ] || v=$(sed -n "s/^$1=//p" "$root/setup/linux-bare-debs.env"); echo "$v"; }
debs_tag=$(debpin LINUX_BARE_DEBS_TAG)
debs_asset=$(debpin LINUX_BARE_DEBS_ASSET)
debs_sha=$(debpin LINUX_BARE_DEBS_SHA256)
debs_url=${FORTRAN_TOOLCHAINS_DEBS_URL:-https://github.com/${FORTRAN_TOOLCHAINS_REPOSITORY:-szaghi/fortran-toolchains}/releases/download}
bundled() { [ -n "$debs_tag" ] && [ -n "$debs_asset" ] && [ -n "$debs_sha" ]; }

setenv() {
  if [ -n "${GITHUB_ENV:-}" ]; then printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"; else printf 'export %s=%q\n' "$1" "$2"; fi
}
addpath() {
  # shellcheck disable=SC2016 # the printed line must keep $PATH literal
  if [ -n "${GITHUB_PATH:-}" ]; then printf '%s\n' "$1" >> "$GITHUB_PATH"; else printf 'export PATH=%q:$PATH\n' "$1"; fi
}
output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; else printf '# %s=%s\n' "$1" "$2"; fi
}

major=$(pin GCC); major=${major%%.*}
compilers="gcc-$major g++-$major gfortran-$major"
export DEBIAN_FRONTEND=noninteractive

base() {
  # a third-party source of the runner's image down (Launchpad's PPA on a GitHub runner) fails only its own index:
  # warn and go on, the Ubuntu archive is what these packages, and the bundle's dependencies, come from
  $sudo apt-get update -qq || echo "::warning::linux-bare: apt-get update reported errors (a source down?)" >&2
  $sudo apt-get install -y -qq --no-install-recommends software-properties-common gpg-agent ca-certificates curl \
    unzip xz-utils make pkg-config python3-venv git > /dev/null
}
ppa() { $sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test > /dev/null; }

# the bundle into $home/debs (once: a cached directory already holds it), checked against the pinned sha256
fetch_bundle() {
  local tmp
  [ "$(cat "$home/debs/.bundle" 2> /dev/null)" = "$debs_tag" ] && return 0
  tmp=$(mktemp -d)
  if ! curl -fsSL --retry 3 -o "$tmp/$debs_asset" "$debs_url/$debs_tag/$debs_asset"; then
    echo "linux-bare: the bundle $debs_tag/$debs_asset cannot be downloaded: the PPA instead" >&2; rm -rf "$tmp"; return 1
  fi
  if [ "$(sha256sum "$tmp/$debs_asset" | cut -d' ' -f1)" != "$debs_sha" ]; then
    echo "linux-bare: the bundle $debs_tag/$debs_asset does not match its pinned sha256: the PPA instead" >&2
    rm -rf "$tmp"; return 1
  fi
  $sudo rm -rf "$home/debs"; mkdir -p "$home/debs"
  tar -xJf "$tmp/$debs_asset" -C "$home/debs"
  echo "$debs_tag" > "$home/debs/.bundle"
  rm -rf "$tmp"
}

case ${1:?usage: linux-bare.sh repo|install|bundle DIR} in
  repo)
    base
    if bundled; then
      output gcc "$debs_tag"
    else
      ppa
      output gcc "$(apt-cache policy "gcc-$major" | sed -n 's/^ *Candidate: *//p')"
    fi
    ;;
  install)
    if bundled && fetch_bundle; then
      # the bundle's packages by file: apt resolves their Ubuntu dependencies from the runner's archive, no PPA
      echo "compiler packages: the bundle $debs_tag ($(find "$home/debs" -maxdepth 1 -name '*.deb' | wc -l) packages)"
      $sudo apt-get install -y -qq --no-install-recommends "$home"/debs/*.deb > /dev/null
    else
      # no bundle, or it failed: the PPA (the repo phase did not add it when a bundle was pinned)
      if bundled; then ppa; $sudo apt-get update -qq; fi
      # apt downloads into (and installs from) the cached directory; packages already there are not downloaded again
      mkdir -p "$home/debs/partial"
      rm -f "$home/debs/.bundle"
      # shellcheck disable=SC2086 # a list of package names
      $sudo apt-get install -y -qq --no-install-recommends -o Dir::Cache::archives="$home/debs" $compilers > /dev/null
    fi
    # apt (root) leaves partial/ (mode 700) and lock (600) there: back to the runner's user, or actions/cache cannot
    # read the directory and only warns that it failed to save it
    $sudo chown -R "$(id -u):$(id -g)" "$home/debs"
    echo "compiler packages: $(find "$home/debs" -maxdepth 1 -name '*.deb' | wc -l) in $home/debs ($(du -sh "$home/debs" | cut -f1))"

    $sudo env CMAKE="$(pin CMAKE)" NINJA="$(pin NINJA)" FPM="$(pin FPM)" "$root/common/install-tools.sh" cmake ninja fpm
    "$root/common/install-venv.sh" --fobis "$home/venv" "$pins"

    # the unversioned names a project's makefile or fobos calls (gfortran, not gfortran-16) at the PPA's compilers,
    # ahead of the runner's own gcc
    mkdir -p "$home/bin"
    for tool in gcc g++ gfortran gcov; do ln -sf "$(command -v "$tool-$major")" "$home/bin/$tool"; done
    echo "gfortran: $("$home/bin/gfortran" -dumpfullversion) ($(readlink "$home/bin/gfortran"))"
    addpath "$home/bin"
    addpath /opt/cmake/bin
    addpath /opt/tools/bin
    addpath "$home/venv/bin"
    setenv FC "gfortran-$major"
    setenv CC "gcc-$major"
    setenv CXX "g++-$major"
    setenv TOOLCHAIN linux-bare
    setenv TOOLCHAIN_OS linux
    setenv TOOLCHAIN_FAMILY gnu
    ;;
  bundle)
    out=${2:?usage: linux-bare.sh bundle DIR}
    base
    ppa
    arch=$(dpkg --print-architecture)
    work=$(mktemp -d)
    mkdir -p "$work/archives/partial" "$work/bundle" "$out"
    # what apt would download for the compilers on this runner, then only the PPA's packages: their Ubuntu
    # dependencies stay with the archive of the runner that installs them (the PPA's versions carry "ppa")
    # shellcheck disable=SC2086 # a list of package names
    $sudo apt-get install -y -qq --download-only --no-install-recommends -o Dir::Cache::archives="$work/archives" \
      $compilers > /dev/null
    for deb in "$work"/archives/*.deb; do
      if dpkg-deb -f "$deb" Version | grep -q ppa; then cp "$deb" "$work/bundle/"; fi
    done
    version=$(apt-cache policy "gcc-$major" | sed -n 's/^ *Candidate: *//p')
    tag="linux-bare-debs-gcc-$(printf '%s' "$version" | tr -c 'A-Za-z0-9.' '-')"
    asset="linux-bare-debs-$arch.tar.xz"
    (cd "$work/bundle" && for deb in *.deb; do dpkg-deb -f "$deb" Package Version | paste -sd' '; done) \
      | sort > "$out/manifest-$arch.txt"
    tar -cJf "$out/$asset" -C "$work/bundle" .
    (cd "$out" && sha256sum "$asset" > "$asset.sha256")
    echo "bundle: $(wc -l < "$out/manifest-$arch.txt") packages of the PPA, $(du -h "$out/$asset" | cut -f1), gcc-$major $version"
    output tag "$tag"
    output asset "$asset"
    output sha256 "$(cut -d' ' -f1 "$out/$asset.sha256")"
    $sudo rm -rf "$work"
    ;;
  *) echo "linux-bare.sh: unknown phase $1" >&2; exit 2 ;;
esac
