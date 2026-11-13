#!/usr/bin/env bash
# The macos-gnu toolchain on a GitHub macOS runner (arm64), called by .github/actions/setup-macos in phases (the action
# restores the HDF5 cache between them). Portable to bash 3.2 (macOS's /bin/bash).
#
#   macos.sh tools lite|full [brew packages...]
#       Homebrew: gcc (the WSL major of the GCC pin), fpm, ninja, pkg-config, open-mpi (full), the extra packages;
#       CMake: Kitware's release binary at its pin; FoBiS pinned in a venv. Exports the environment contract (FC = the
#       Homebrew gfortran-<major>, CC/CXX = Apple clang) and prints the installed gfortran and Open MPI versions as step
#       outputs (gfortran=, openmpi=) for the HDF5 cache key.
#   macos.sh hdf5
#       HDF5 at the pinned commit, built by Open MPI's wrappers (mpifort on the contract's gfortran) into
#       $HOME/.fortran-toolchains/hdf5 unless the cache restored it; exports MPIFC, MPIRUN, HDF5_ROOT.
#
# Writes to $GITHUB_ENV, $GITHUB_PATH and $GITHUB_OUTPUT inside a job; prints `export` lines otherwise.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
pins=$root/versions.env
home=${FORTRAN_TOOLCHAINS_HOME:-$HOME/.fortran-toolchains}
pin() { sed -n "s/^$1=//p" "$pins"; }

setenv() {   # setenv NAME VALUE: for the later steps of the job, and for this script
  if [ -n "${GITHUB_ENV:-}" ]; then printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"; else printf 'export %s=%q\n' "$1" "$2"; fi
  export "$1=$2"
}
addpath() {
  # shellcheck disable=SC2016 # the printed line must keep $PATH literal
  if [ -n "${GITHUB_PATH:-}" ]; then printf '%s\n' "$1" >> "$GITHUB_PATH"; else printf 'export PATH=%q:$PATH\n' "$1"; fi
  PATH=$1:$PATH
}
output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; else printf '# %s=%s\n' "$1" "$2"; fi
}

gcc_major=$(pin GCC); gcc_major=${gcc_major%%.*}
fc=gfortran-$gcc_major

case ${1:?usage: macos.sh tools lite|full [packages...] | hdf5} in
  tools)
    flavour=${2:?usage: macos.sh tools lite|full [packages...]}; shift 2
    case $flavour in lite|full) ;; *) echo "macos.sh: flavour '$flavour' is not lite or full" >&2; exit 2 ;; esac
    pkgs="gcc fpm ninja pkg-config"
    [ "$flavour" = full ] && pkgs="$pkgs open-mpi"
    export HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1
    # shellcheck disable=SC2086 # a list of package names
    brew install $pkgs "$@"
    command -v "$fc" >/dev/null || {
      echo "::error title=version drift::Homebrew's gcc has no $fc: versions.env pins GCC $(pin GCC)"; exit 1; }

    # CMake at its pin (Homebrew has only its newest)
    cmake=$(pin CMAKE) f=cmake-$(pin CMAKE)-macos-universal.tar.gz
    if [ ! -x "$home/cmake/CMake.app/Contents/bin/cmake" ]; then
      mkdir -p "$home/cmake" && cd "$home"
      curl -fsSLO "https://github.com/Kitware/CMake/releases/download/v$cmake/$f"
      curl -fsSL "https://github.com/Kitware/CMake/releases/download/v$cmake/cmake-$cmake-SHA-256.txt" \
        | grep " $f\$" | shasum -a 256 -c
      tar xzf "$f" -C "$home/cmake" --strip-components=1 && rm "$f"
    fi
    addpath "$home/cmake/CMake.app/Contents/bin"

    "$root/common/install-venv.sh" --fobis "$home/venv" "$pins"
    addpath "$home/venv/bin"

    setenv FC "$fc"
    setenv CC clang
    setenv CXX clang++
    setenv TOOLCHAIN macos-gnu
    setenv TOOLCHAIN_OS macos
    setenv TOOLCHAIN_FAMILY gnu
    output gfortran "$("$fc" -dumpfullversion)"
    if [ "$flavour" = full ]; then
      setenv OMPI_FC "$fc"   # Open MPI's mpifort on the contract's gfortran, not on another Homebrew one
      setenv PRTE_MCA_rmaps_default_mapping_policy :oversubscribe
      output openmpi "$(mpirun --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    fi
    ;;
  hdf5)
    export OMPI_FC=${OMPI_FC:-$fc}
    if [ ! -f "$home/hdf5/lib/libhdf5_fortran.a" ]; then
      HDF5_PREFIX=$home/hdf5 HDF5_COMMIT=$(pin HDF5_COMMIT) JOBS=$(sysctl -n hw.ncpu) TMPDIR=${RUNNER_TEMP:-${TMPDIR:-/tmp}} \
        "$root/common/build-hdf5.sh" mpicc mpifort
    else
      echo "HDF5 restored from the cache: $home/hdf5"
    fi
    setenv MPIFC mpifort
    setenv MPIRUN mpirun
    setenv HDF5_ROOT "$home/hdf5"
    addpath "$home/hdf5/bin"
    ;;
  *) echo "macos.sh: unknown phase $1" >&2; exit 2 ;;
esac
