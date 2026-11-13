#!/usr/bin/env bash
# The linux-bare toolchain on a fresh Ubuntu runner, for the jobs that must test a fresh machine rather than an image
# (installers): gcc/g++/gfortran of the GCC pin's major from the ubuntu-toolchain-r/test PPA (the only gcc 16 for
# Ubuntu 24.04 is its snapshot, a same-major drift the checks warn about), CMake, ninja, fpm at their pins in /opt,
# FoBiS pinned in a venv. Exports the environment contract. Root or sudo.
#
# Writes to $GITHUB_ENV and $GITHUB_PATH inside a job; prints `export` lines otherwise.
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

major=$(pin GCC); major=${major%%.*}
export DEBIAN_FRONTEND=noninteractive
$sudo apt-get update -qq
$sudo apt-get install -y -qq --no-install-recommends software-properties-common gpg-agent ca-certificates curl \
  unzip xz-utils make pkg-config python3-venv git > /dev/null
$sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test > /dev/null
$sudo apt-get install -y -qq --no-install-recommends "gcc-$major" "g++-$major" "gfortran-$major" > /dev/null

$sudo env CMAKE="$(pin CMAKE)" NINJA="$(pin NINJA)" FPM="$(pin FPM)" "$root/common/install-tools.sh" cmake ninja fpm
"$root/common/install-venv.sh" --fobis "$home/venv" "$pins"

addpath /opt/cmake/bin
addpath /opt/tools/bin
addpath "$home/venv/bin"
setenv FC "gfortran-$major"
setenv CC "gcc-$major"
setenv CXX "g++-$major"
setenv TOOLCHAIN linux-bare
setenv TOOLCHAIN_OS linux
setenv TOOLCHAIN_FAMILY gnu
