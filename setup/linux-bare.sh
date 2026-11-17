#!/usr/bin/env bash
# The linux-bare toolchain on a fresh Ubuntu runner, for the jobs that must test a fresh machine rather than an image
# (installers): gcc/g++/gfortran at the exact GCC pin, built from the GNU release by this repository and published as
# its release asset (no PPA, no Launchpad), CMake, ninja, fpm at their pins in /opt, FoBiS pinned in a venv. Root or
# sudo. Called by .github/actions/setup-linux-bare in two phases, the action restoring the cache of the compiler's
# archive between them:
#
#   linux-bare.sh repo       the base packages, and the libraries the compiler links at run time (gmp, mpfr, mpc,
#                                  isl, zlib), from Ubuntu's archive; prints the cache key as a step output (gcc=: the
#                                  toolchain's release tag)
#   linux-bare.sh install    the compiler: the asset pinned in setup/linux-bare-gcc.env, downloaded once into
#                                  $FORTRAN_TOOLCHAINS_HOME/gcc (the cached directory), checked against its pinned
#                                  sha256, extracted at its prefix (/opt/gcc/bin/<GCC>, the WSL box's layout), its
#                                  libraries registered with ldconfig; the tools, versioned and unversioned links to
#                                  the compilers ahead of the runner's own; exports the contract. No pin, or the
#                                  download or the check failing, is an error: there is no other source.
#   linux-bare.sh build DIR  on a fresh Ubuntu: the GCC release of the pin from the GNU mirrors, its signature checked
#                                  against GNU's keyring (the signer's fingerprint and the tarball's sha256 pinned in
#                                  setup/linux-bare-gcc.env), built (C, C++, Fortran) and installed at the prefix,
#                                  packed as DIR/<asset> with its .sha256 and a manifest; prints the tag, the asset and
#                                  the sha256 as outputs (gcc.yml publishes them)
#
# The pins of setup/linux-bare-gcc.env can be overridden by the environment (gcc.yml's check, the tests), and
# FORTRAN_TOOLCHAINS_GCC_URL replaces the releases' base URL (file:// in the tests).
#
# Writes to $GITHUB_ENV, $GITHUB_PATH and $GITHUB_OUTPUT inside a job; prints `export` lines otherwise.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
pins=$root/versions.env
pin() { sed -n "s/^$1=//p" "$pins"; }
gccpin() { local v; v=$(printenv "$1" || true); [ -n "$v" ] || v=$(sed -n "s/^$1=//p" "$root/setup/linux-bare-gcc.env"); echo "$v"; }
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

gcc=$(pin GCC)
major=${gcc%%.*}
prefix=/opt/gcc/bin/$gcc
tag=$(gccpin LINUX_BARE_GCC_TAG)
asset=$(gccpin LINUX_BARE_GCC_ASSET)
sha=$(gccpin LINUX_BARE_GCC_SHA256)
url=${FORTRAN_TOOLCHAINS_GCC_URL:-https://github.com/${FORTRAN_TOOLCHAINS_REPOSITORY:-szaghi/fortran-toolchains}/releases/download}
export DEBIAN_FRONTEND=noninteractive

base() {
  $sudo apt-get update -qq || echo "::warning::linux-bare: apt-get update reported errors (a source down?)" >&2
  $sudo apt-get install -y -qq --no-install-recommends ca-certificates curl unzip xz-utils make pkg-config \
    python3-venv git binutils libc6-dev libgmp10 libmpfr6 libmpc3 libisl23 zlib1g "$@" > /dev/null
}

case ${1:?usage: linux-bare.sh repo|install|build DIR} in
  repo)
    base
    output gcc "${tag:-unpinned}"
    ;;
  install)
    if [ -z "$tag" ] || [ -z "$asset" ] || [ -z "$sha" ]; then
      echo "linux-bare: no toolchain pinned in setup/linux-bare-gcc.env (run the GCC workflow, then paste its pins)" >&2
      exit 1
    fi
    mkdir -p "$home/gcc"
    if [ "$(cat "$home/gcc/.tag" 2> /dev/null)" != "$tag" ] || [ ! -f "$home/gcc/$asset" ]; then
      rm -f "$home/gcc/$asset" "$home/gcc/.tag"
      curl -fsSL --retry 5 --retry-delay 10 -o "$home/gcc/$asset" "$url/$tag/$asset" \
        || { echo "linux-bare: the toolchain $tag/$asset cannot be downloaded from $url" >&2; exit 1; }
    fi
    if [ "$(sha256sum "$home/gcc/$asset" | cut -d' ' -f1)" != "$sha" ]; then
      rm -f "$home/gcc/$asset"
      echo "linux-bare: the toolchain $tag/$asset does not match its pinned sha256" >&2; exit 1
    fi
    echo "$tag" > "$home/gcc/.tag"
    $sudo tar -xJf "$home/gcc/$asset" -C /
    [ -x "$prefix/bin/gfortran" ] || { echo "linux-bare: $asset has no $prefix/bin/gfortran" >&2; exit 1; }
    # the compiler's runtime (libgfortran, libstdc++, libgcc_s) for every program it builds, without LD_LIBRARY_PATH
    printf '%s\n' "$prefix/lib64" "$prefix/lib" | $sudo tee /etc/ld.so.conf.d/linux-bare-gcc.conf > /dev/null
    $sudo ldconfig
    echo "compiler: the toolchain $tag ($(du -sh "$home/gcc/$asset" | cut -f1)) at $prefix"

    $sudo env CMAKE="$(pin CMAKE)" NINJA="$(pin NINJA)" FPM="$(pin FPM)" "$root/common/install-tools.sh" cmake ninja fpm
    "$root/common/install-venv.sh" --fobis "$home/venv" "$pins"

    # the names a project's makefile or fobos calls, unversioned (gfortran) and versioned (gfortran-16, the contract's
    # FC), at the toolchain's compilers, ahead of the runner's own gcc
    mkdir -p "$home/bin"
    for tool in gcc g++ gfortran gcov; do
      ln -sf "$prefix/bin/$tool" "$home/bin/$tool"
      ln -sf "$prefix/bin/$tool" "$home/bin/$tool-$major"
    done
    echo "gfortran: $("$home/bin/gfortran" -dumpfullversion) ($prefix)"
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
  build)
    out=${2:?usage: linux-bare.sh build DIR}
    [ "$(gccpin GCC_SOURCE_VERSION)" = "$gcc" ] \
      || { echo "linux-bare: the source pins are for GCC $(gccpin GCC_SOURCE_VERSION), versions.env says $gcc" >&2; exit 1; }
    base gpgv build-essential libgmp-dev libmpfr-dev libmpc-dev libisl-dev zlib1g-dev file
    work=$(mktemp -d)
    mkdir -p "$out"
    src=gcc-$gcc.tar.xz
    # the release from the GNU mirrors (the redirector first), its signature against GNU's keyring
    for m in https://ftpmirror.gnu.org/gcc https://ftp.gnu.org/gnu/gcc https://sourceware.org/pub/gcc/releases; do
      if curl -fsSL --retry 3 -o "$work/$src" "$m/gcc-$gcc/$src" && curl -fsSL --retry 3 -o "$work/$src.sig" "$m/gcc-$gcc/$src.sig"; then
        echo "source: $m/gcc-$gcc/$src"; break
      fi
      rm -f "$work/$src" "$work/$src.sig"
    done
    [ -f "$work/$src" ] || { echo "linux-bare: $src from no mirror" >&2; exit 1; }
    curl -fsSL --retry 3 -o "$work/gnu-keyring.gpg" https://ftp.gnu.org/gnu/gnu-keyring.gpg \
      || curl -fsSL --retry 3 -o "$work/gnu-keyring.gpg" https://ftpmirror.gnu.org/gnu-keyring.gpg
    signer=$(gpgv --status-fd 1 --keyring "$work/gnu-keyring.gpg" "$work/$src.sig" "$work/$src" 2> /dev/null \
      | sed -n 's/^\[GNUPG:\] VALIDSIG \([0-9A-F]*\) .*/\1/p')
    [ "$signer" = "$(gccpin GCC_SOURCE_SIGNER)" ] \
      || { echo "linux-bare: $src not signed by the pinned key (signer: ${signer:-none})" >&2; exit 1; }
    [ "$(sha256sum "$work/$src" | cut -d' ' -f1)" = "$(gccpin GCC_SOURCE_SHA256)" ] \
      || { echo "linux-bare: $src does not match its pinned sha256" >&2; exit 1; }
    echo "source: signed by $signer, sha256 as pinned"
    tar -xJf "$work/$src" -C "$work"
    mkdir -p "$work/build"
    # C, C++ and Fortran, no bootstrap (the runner's gcc 13 builds it once), the runtime and the libraries of Ubuntu's
    # archive (gmp, mpfr, mpc, isl, zlib), which repo installs on the consumer's runner
    (cd "$work/build" && "../gcc-$gcc/configure" --prefix="$prefix" --enable-languages=c,c++,fortran \
      --disable-multilib --disable-bootstrap --disable-nls --with-system-zlib --enable-checking=release \
      > "$out/configure.log" 2>&1) || { tail -30 "$out/configure.log"; exit 1; }
    (cd "$work/build" && make -j"$(nproc)" > "$out/make.log" 2>&1) || { tail -40 "$out/make.log"; exit 1; }
    (cd "$work/build" && $sudo make install-strip > "$out/install.log" 2>&1) || { tail -20 "$out/install.log"; exit 1; }
    ubuntu=$(sed -n 's/^VERSION_ID="*\([^"]*\)"*$/\1/p' /etc/os-release)
    arch=$(dpkg --print-architecture)
    tag="linux-bare-gcc-$gcc-ubuntu$ubuntu"
    asset="gcc-$gcc-ubuntu$ubuntu-$arch.tar.xz"
    "$prefix/bin/gfortran" -v > "$out/manifest-$arch.txt" 2>&1
    tar -cJf "$out/$asset" -C / "${prefix#/}"
    (cd "$out" && sha256sum "$asset" > "$asset.sha256")
    echo "toolchain: gfortran $("$prefix/bin/gfortran" -dumpfullversion) at $prefix, $(du -h "$out/$asset" | cut -f1)"
    output tag "$tag"
    output asset "$asset"
    output sha256 "$(cut -d' ' -f1 "$out/$asset.sha256")"
    $sudo rm -rf "$work"
    ;;
  *) echo "linux-bare.sh: unknown phase $1" >&2; exit 2 ;;
esac
