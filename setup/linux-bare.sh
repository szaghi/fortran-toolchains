#!/usr/bin/env bash
# The linux-bare toolchain on a fresh Ubuntu runner, for the jobs that must test a fresh machine rather than an image
# (installers): gcc/g++/gfortran of the GCC pin's major from the ubuntu-toolchain-r/test PPA (the only gcc 16 for
# Ubuntu 24.04 is its snapshot, a same-major drift the checks warn about), CMake, ninja, fpm at their pins in /opt,
# FoBiS pinned in a venv. Root or sudo. Called by .github/actions/setup-linux-bare in two phases, the action
# restoring the cache of the compiler's packages between them (388 MB from the PPA for gcc 16, minutes to download):
#
#   linux-bare.sh repo       the PPA added; prints the compiler's PPA version as a step output (gcc=) for the
#                                  cache key
#   linux-bare.sh install    the compiler, apt's archives in $FORTRAN_TOOLCHAINS_HOME/debs (the cached directory:
#                                  restored packages are not downloaded again), the tools, unversioned links to the
#                                  compilers ahead of the runner's own; exports the contract
#
# Writes to $GITHUB_ENV, $GITHUB_PATH and $GITHUB_OUTPUT inside a job; prints `export` lines otherwise.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
pins=$root/versions.env
pin() { sed -n "s/^$1=//p" "$pins"; }
sudo=; [ "$(id -u)" = 0 ] || sudo=sudo
home=${FORTRAN_TOOLCHAINS_HOME:-$HOME/.fortran-toolchains}

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

case ${1:?usage: linux-bare.sh repo|install} in
  repo)
    $sudo apt-get update -qq
    $sudo apt-get install -y -qq --no-install-recommends software-properties-common gpg-agent ca-certificates curl \
      unzip xz-utils make pkg-config python3-venv git > /dev/null
    $sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test > /dev/null
    output gcc "$(apt-cache policy "gcc-$major" | sed -n 's/^ *Candidate: *//p')"
    ;;
  install)
    # apt downloads into (and installs from) the cached directory; packages already there are not downloaded again
    mkdir -p "$home/debs/partial"
    # shellcheck disable=SC2086 # a list of package names
    $sudo apt-get install -y -qq --no-install-recommends -o Dir::Cache::archives="$home/debs" $compilers > /dev/null
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
  *) echo "linux-bare.sh: unknown phase $1" >&2; exit 2 ;;
esac
