#!/usr/bin/env bash
# Run inside an image at build time: every component's version must equal its pin, the build argument of the same
# name (versions.env, the latest installed on the WSL box). The components to check are the arguments, e.g.
#
#   check-versions.sh GCC FOBIS FORD FPM ...
#
# Exit 1 on any mismatch or missing component.
set -euo pipefail

# the first X.Y[.Z] of a command's output, empty if the command fails
version_of() { "$@" 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true; }

probe() {
  case $1 in
    GCC)        version_of gfortran -dumpfullversion ;;
    OPENMPI)    version_of mpirun --version ;;
    INTEL_MPI)  version_of mpirun --version ;;
    IFX)        version_of ifx --version ;;
    NVHPC)      version_of nvfortran --version ;;
    CUDA)       find "${NVHPC_ROOT:-/nonexistent}/cuda" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null \
                  | grep -E '^[0-9]+\.[0-9]+$' | sort -V | tail -1 || true ;;
    UBUNTU)     sed -n 's/^VERSION_ID="\{0,1\}\([0-9.]*\)"\{0,1\}$/\1/p' /etc/os-release ;;
    HDF5)       sed -n 's/^ *HDF5 Version: *//p' /opt/hdf5/lib/libhdf5.settings 2>/dev/null || true ;;
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
    NUMPY)      version_of python -c 'import numpy; print(numpy.__version__)' ;;
    H5PY)       version_of python -c 'import h5py; print(h5py.__version__)' ;;
    *)          echo "check-versions.sh: no probe for $1" >&2; return 1 ;;
  esac
}

fail=0
for key in "$@"; do
  want=${!key:-}
  have=$(probe "$key")
  if [[ -z $want ]]; then status="no pin (build argument $key unset)"; fail=1
  elif [[ $have == "$want" ]]; then status=ok
  else status="MISMATCH (image has ${have:-nothing})"; fail=1
  fi
  printf '%-12s %-12s %s\n' "$key" "${want:--}" "$status"
done
exit $fail
