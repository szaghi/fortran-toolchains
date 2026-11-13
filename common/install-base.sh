#!/usr/bin/env bash
# The distribution packages of every image (Debian or Ubuntu base), and the system-wide git setting the CI jobs need.
#
#   install-base.sh lite      what the tools and the CI scripts call: git, make, jq, GNU awk, Python venv, zsh, the ICU
#                             library PowerShell loads (libicu<N>: the name carries the distribution's ICU version)
#   install-base.sh full      the libraries the projects link besides MPI/HDF5: zlib, LZ4, LZMA, FFTW 3
#   install-base.sh gui       the X11/Wayland development headers SDL builds against, Xvfb, Mesa (llvmpipe), glxinfo
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
case ${1:?usage: install-base.sh lite|full|gui} in
  lite)
    icu=$(apt-cache search --names-only '^libicu[0-9]+$' | cut -d' ' -f1 | sort -V | tail -1)
    apt-get install -y --no-install-recommends pkg-config git make jq gawk python3 python3-venv zsh "$icu" \
                                               ca-certificates curl xz-utils bzip2 unzip
    # every repository is safe: in a job container actions/checkout marks the workspace safe only in a temporary HOME,
    # so any later git (the coverage outputs of ci.yml, the git diff checks) runs as root on a checkout owned by the
    # runner user and dies with "detected dubious ownership"; checked by each image on a repository of another user
    git config --system --add safe.directory '*'
    ;;
  full)
    apt-get install -y --no-install-recommends zlib1g-dev liblz4-dev liblzma-dev libfftw3-dev
    ;;
  gui)
    apt-get install -y --no-install-recommends \
      libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxfixes-dev libxss-dev libxtst-dev \
      libwayland-dev libxkbcommon-dev libegl-dev libdbus-1-dev libdecor-0-dev \
      xvfb xauth libgl1-mesa-dri libglx-mesa0 mesa-utils
    ;;
  *) echo "install-base.sh: unknown set $1" >&2; exit 2 ;;
esac
rm -rf /var/lib/apt/lists/*
