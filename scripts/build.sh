#!/usr/bin/env bash
# Build a toolchain image locally, or print what the Build workflow needs to build it. The versions come from
# versions.env (the build arguments of every Dockerfile), the tag from the vendor, its version and the flavour:
#
#   scripts/build.sh gnu full [docker build options]   docker build -t <tag> --target full -f gnu/Dockerfile ... .
#   scripts/build.sh gnu full --tag                      the image tag, e.g. ghcr.io/szaghi/fortran-toolchains:gnu-16.2
#   scripts/build.sh gnu full --build-args               the build arguments, one KEY=VALUE per line
#
# Tags: <vendor>-<major.minor> for the full flavour (the one the projects use), <vendor>-<major.minor>-<flavour> for
# the others. Environment: REGISTRY (default ghcr.io/szaghi/fortran-toolchains).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
registry=${REGISTRY:-ghcr.io/szaghi/fortran-toolchains}

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[[ $# -ge 2 ]] || usage
vendor=$1 flavour=$2; shift 2
[[ -f $root/$vendor/Dockerfile ]] || { echo "error: no $vendor/Dockerfile" >&2; exit 2; }
# the flavours are the Dockerfile's public stages; the others (tools, build) are internal
[[ $flavour =~ ^(lite|full|gui)$ ]] || { echo "error: flavour '$flavour' is not lite, full or gui" >&2; exit 2; }
grep -qE "^FROM .* AS ${flavour}\$" "$root/$vendor/Dockerfile" \
  || { echo "error: $vendor/Dockerfile has no flavour (stage) '$flavour'" >&2; exit 2; }

build_args=$(grep -E '^[A-Z0-9_]+=' "$root/versions.env")
value() { sed -n "s/^$1=//p" <<< "$build_args"; }

# the version a vendor's tag carries: its compiler's
case $vendor in
  gnu)    version=$(value GCC) ;;
  nvhpc)  version=$(value NVHPC) ;;
  oneapi) version=$(value IFX) ;;
  *)      echo "error: no version rule for vendor '$vendor'" >&2; exit 2 ;;
esac
tag="$registry:$vendor-$(cut -d. -f1,2 <<< "$version")"
# the toolchain id of the environment contract (TOOLCHAIN), a build argument besides the versions
build_args+=$'\n'"TOOLCHAIN=linux-$vendor-$(cut -d. -f1,2 <<< "$version")"
[[ $flavour == full ]] || tag="$tag-$flavour"

case ${1:-} in
  --tag)        echo "$tag"; exit 0 ;;
  --build-args) echo "$build_args"; exit 0 ;;
esac

args=()
while IFS= read -r kv; do args+=(--build-arg "$kv"); done <<< "$build_args"
set -x
docker build --target "$flavour" "${args[@]}" -t "$tag" -f "$root/$vendor/Dockerfile" "$@" "$root"
