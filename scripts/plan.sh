#!/usr/bin/env bash
# Resolve toolchain ids into the matrices of the matrix workflow, one line per runner kind (GitHub Actions outputs):
#
#   scripts/plan.sh [--display] TOOLCHAIN...
#     linux=[{"toolchain":"linux-gnu","image":"ghcr.io/.../fortran-toolchains:gnu-16.2"},...]
#     macos=["macos-gnu"]
#     windows=["windows-gnu"]
#
# Ids carry no version: linux-<vendor> (a directory with a Dockerfile: gnu, nvhpc, oneapi), macos-gnu, windows-gnu.
# A Linux id resolves to the vendor's current image (scripts/build.sh --tag, from versions.env): the full flavour, the
# gui flavour with --display. So a versions.env bump reaches every project without editing its workflow.
# Environment: REGISTRY (default ghcr.io/szaghi/fortran-toolchains). Exit 2 on an unknown id.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
flavour=full
[ "${1:-}" = --display ] && { flavour=gui; shift; }
[ $# -gt 0 ] || { echo "usage: plan.sh [--display] TOOLCHAIN..." >&2; exit 2; }

linux=() macos=() windows=()
for id in "$@"; do
  case $id in
    linux-*)
      vendor=${id#linux-}
      [ -f "$root/$vendor/Dockerfile" ] || { echo "plan.sh: unknown toolchain $id (no $vendor/Dockerfile)" >&2; exit 2; }
      linux+=("{\"toolchain\":\"$id\",\"image\":\"$("$root/scripts/build.sh" "$vendor" "$flavour" --tag)\"}")
      ;;
    macos-gnu)   macos+=("\"$id\"") ;;
    windows-gnu) windows+=("\"$id\"") ;;
    *) echo "plan.sh: unknown toolchain $id (linux-<vendor>, macos-gnu, windows-gnu)" >&2; exit 2 ;;
  esac
done

join() { local IFS=,; echo "[$*]"; }
echo "linux=$(join "${linux[@]+"${linux[@]}"}")"
echo "macos=$(join "${macos[@]+"${macos[@]}"}")"
echo "windows=$(join "${windows[@]+"${windows[@]}"}")"
