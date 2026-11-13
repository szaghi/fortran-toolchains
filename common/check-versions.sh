#!/usr/bin/env bash
# Check components against their pins (versions.env, the latest installed on the WSL box). Run inside every image at
# build time, and by every setup action on its runner. Portable to bash 3.2 (macOS's /bin/bash) and MSYS2.
#
#   check-versions.sh [--policy exact|major] [--pins FILE] KEY...      e.g. check-versions.sh GCC FPM CMAKE
#
# The pin of KEY is the environment variable KEY (the images' build arguments) or, with --pins, the KEY=VALUE line of
# FILE (read, never sourced). Policies:
#   exact (default)  any difference fails: the images, built from the pins
#   major            same major version = a warning (a GitHub Actions annotation), another major = a failure: the
#                    rolling platforms (Homebrew, MSYS2, the toolchain PPA), which cannot install an exact version
# GCC is probed through $FC when set (gfortran-16 on macOS), gfortran otherwise. Exit 1 on any failure.
set -uo pipefail

policy=exact pins=
while [ $# -gt 0 ]; do
  case $1 in
    --policy) policy=${2:?--policy needs exact or major}; shift 2 ;;
    --pins)   pins=${2:?--pins needs a file}; shift 2 ;;
    *)        break ;;
  esac
done
case $policy in exact|major) ;; *) echo "check-versions.sh: unknown policy '$policy'" >&2; exit 2 ;; esac

# the first X.Y[.Z] of a command's output, empty if the command fails or is missing
version_of() { "$@" 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true; }

probe() {
  case $1 in
    GCC)        version_of "${FC:-gfortran}" -dumpfullversion ;;
    OPENMPI)    version_of mpirun --version ;;
    INTEL_MPI)  version_of mpirun --version ;;
    IFX)        version_of ifx --version ;;
    NVHPC)      version_of nvfortran --version ;;
    CUDA)       for d in "${NVHPC_ROOT:-/nonexistent}"/cuda/[0-9]*.[0-9]*; do [ -d "$d" ] && basename "$d"; done \
                  | sort -t. -k1,1n -k2,2n | tail -1 ;;
    UBUNTU)     sed -n 's/^VERSION_ID="\{0,1\}\([0-9.]*\)"\{0,1\}$/\1/p' /etc/os-release 2>/dev/null ;;
    HDF5)       sed -n 's/^ *HDF5 Version: *//p' "${HDF5_ROOT:-/opt/hdf5}/lib/libhdf5.settings" 2>/dev/null ;;
    NODE)       version_of node --version ;;
    FOBIS)      version_of fobis --version ;;
    FORD)       version_of ford --version ;;
    FORMAL)     version_of formal --version ;;
    FPM)        version_of fpm --version ;;
    CMAKE)      version_of cmake --version ;;
    NINJA)      version_of ninja --version ;;
    SHELLCHECK) version_of shellcheck --version ;;
    ZSH)        version_of zsh --version ;;
    FISH)       version_of fish --version ;;
    PWSH)       version_of pwsh --version ;;
    NUMPY)      version_of python3 -c 'import numpy; print(numpy.__version__)' ;;
    H5PY)       version_of python3 -c 'import h5py; print(h5py.__version__)' ;;
    *)          echo "check-versions.sh: no probe for $1" >&2; return 1 ;;
  esac
}

pin() {
  if [ -n "$pins" ]; then sed -n "s/^$1=//p" "$pins" | head -1
  else eval "printf '%s' \"\${$1:-}\""; fi
}

fail=0
for key in "$@"; do
  want=$(pin "$key")
  have=$(probe "$key") || { fail=1; continue; }
  if [ -z "$want" ]; then
    status="no pin for $key"; fail=1
  elif [ "$have" = "$want" ]; then
    status=ok
  elif [ -z "$have" ]; then
    status="MISSING"; fail=1
  elif [ "$policy" = major ] && [ "${have%%.*}" = "${want%%.*}" ]; then
    status="DRIFT (found $have, same major)"
    echo "::warning title=version drift::$key: pinned $want, found $have (same major, accepted on a rolling platform)"
  else
    status="MISMATCH (found $have)"; fail=1
    [ "$policy" = major ] && echo "::error title=version drift::$key: pinned $want, found $have (another major)"
  fi
  printf '%-12s %-12s %s\n' "$key" "${want:--}" "$status"
done
exit $fail
