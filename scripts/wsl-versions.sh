#!/usr/bin/env bash
# Check versions.env against the WSL box: every toolchain component pinned there must be the latest installed on WSL
# (the rule of this repository). Run on WSL.
#
#   scripts/wsl-versions.sh           table of pinned vs WSL, exit 1 on any drift or missing component
#   scripts/wsl-versions.sh --write   rewrite versions.env with the WSL versions (HDF5_COMMIT is kept), then exit 0
#
# Environment: ADAM_DIR (default ~/fortran/adam), whose lib/hdf5/develop/gnu/<GCC> build gives the HDF5 version.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pins="$root/versions.env"
adam=${ADAM_DIR:-$HOME/fortran/adam}

# the newest entry of a directory whose name matches a pattern (version sort), empty if none
newest() { find "$1" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | grep -E "$2" | sort -V | tail -1 || true; }
# the first X.Y[.Z] of a command's output, empty if the command is missing
version_of() {
  if command -v "$1" >/dev/null 2>&1; then "$@" 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true; fi
}

declare -A wsl
wsl[GCC]=$(newest /opt/gcc/bin '^[0-9]+\.[0-9]+\.[0-9]+$')
# the newest Open MPI built by that gcc (/opt/openmpi/bin/<ver>/gnu/<gcc>)
wsl[OPENMPI]=$(find /opt/openmpi/bin -mindepth 3 -maxdepth 3 -path "*/gnu/${wsl[GCC]}" -printf '%P\n' 2>/dev/null \
               | cut -d/ -f1 | sort -V | tail -1 || true)
wsl[HDF5]=$(sed -n 's/^ *HDF5 Version: *//p' "$adam/lib/hdf5/develop/gnu/${wsl[GCC]}/lib/libhdf5.settings" 2>/dev/null || true)
nvhpc_root=/opt/nvidia/hpc_sdk/Linux_x86_64
wsl[NVHPC]=$(newest "$nvhpc_root" '^[0-9]+\.[0-9]+$')
wsl[CUDA]=$(newest "$nvhpc_root/${wsl[NVHPC]}/cuda" '^[0-9]+\.[0-9]+$')
wsl[IFX]=$(version_of /opt/intel/oneapi/compiler/latest/bin/ifx --version)
wsl[INTEL_MPI]=$(basename "$(readlink -f /opt/intel/oneapi/mpi/latest 2>/dev/null)" 2>/dev/null || true)
node_bin=$(command -v node || find "$HOME/.nvm/versions/node" -path '*/bin/node' 2>/dev/null | sort -V | tail -1 || true)
wsl[NODE]=$([[ -n $node_bin ]] && version_of "$node_bin" --version)
wsl[FOBIS]=$(version_of fobis --version)
wsl[FORD]=$(version_of ford --version)
wsl[FORMAL]=$(version_of formal --version)
wsl[FPM]=$(version_of fpm --version)
wsl[CMAKE]=$(version_of cmake --version)
wsl[NINJA]=$(version_of ninja --version)
wsl[SHELLCHECK]=$(version_of shellcheck --version)
wsl[ZSH]=$(version_of zsh --version)
wsl[FISH]=$(version_of fish --version)
wsl[PWSH]=$(version_of pwsh --version)

keys=$(grep -oE '^[A-Z0-9_]+=' "$pins" | tr -d =)

if [[ ${1:-} == --write ]]; then
  for k in $keys; do
    [[ $k == HDF5_COMMIT ]] && continue
    [[ -n ${wsl[$k]:-} ]] || { echo "error: $k not found on WSL, versions.env not written" >&2; exit 1; }
  done
  tmp=$(mktemp)
  while IFS= read -r line; do
    k=${line%%=*}
    if [[ $line =~ ^[A-Z0-9_]+= && $k != HDF5_COMMIT ]]; then echo "$k=${wsl[$k]}"; else echo "$line"; fi
  done < "$pins" > "$tmp"
  cat "$tmp" > "$pins" && rm -f "$tmp"   # keeps the mode of versions.env (mktemp makes 600)
  echo "versions.env rewritten from WSL (HDF5_COMMIT kept: check it against the source of the HDF5 build)"
  exit 0
fi

drift=0
printf '%-12s %-14s %-14s %s\n' COMPONENT PINNED WSL STATUS
for k in $keys; do
  pinned=$(sed -n "s/^$k=//p" "$pins")
  if [[ $k == HDF5_COMMIT ]]; then
    printf '%-12s %-14s %-14s %s\n' "$k" "${pinned:0:12}" - 'not checkable on WSL'
    continue
  fi
  have=${wsl[$k]:-}
  if [[ -z $have ]]; then status='MISSING on WSL'; drift=1
  elif [[ $have == "$pinned" ]]; then status=ok
  else status=DRIFT; drift=1
  fi
  printf '%-12s %-14s %-14s %s\n' "$k" "$pinned" "${have:--}" "$status"
done
exit $drift
