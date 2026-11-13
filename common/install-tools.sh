#!/usr/bin/env bash
# Install the CI tools of every image, at their versions.env pins (the build arguments, in the environment), as upstream
# release binaries; checksums verified where upstream publishes them (CMake, Node, fpm, PowerShell), ninja, ShellCheck
# and fish publish none. Needs curl, unzip, xz, iconv, sha256sum (any glibc base).
#
#   install-tools.sh cmake    CMake ($CMAKE) in /opt/cmake
#   install-tools.sh tools    ninja, fpm, ShellCheck, fish in /opt/tools/bin; Node ($NODE) in /opt/node, PowerShell
#                             ($PWSH) in /opt/pwsh, both linked into /opt/tools/bin
set -euo pipefail

work=$(mktemp -d); cd "$work"
trap 'rm -rf "$work"' EXIT
gh=https://github.com

case ${1:?usage: install-tools.sh cmake|tools} in
  cmake)
    f=cmake-${CMAKE:?}-linux-x86_64.tar.gz
    curl -fsSLO "$gh/Kitware/CMake/releases/download/v$CMAKE/$f"
    curl -fsSL "$gh/Kitware/CMake/releases/download/v$CMAKE/cmake-$CMAKE-SHA-256.txt" | grep " $f\$" | sha256sum -c
    mkdir -p /opt/cmake && tar xzf "$f" -C /opt/cmake --strip-components=1
    ;;
  tools)
    mkdir -p /opt/tools/bin /opt/node /opt/pwsh
    curl -fsSLO "$gh/ninja-build/ninja/releases/download/v${NINJA:?}/ninja-linux.zip"
    unzip -q ninja-linux.zip -d /opt/tools/bin

    f=node-v${NODE:?}-linux-x64.tar.xz
    curl -fsSLO "https://nodejs.org/dist/v$NODE/$f"
    curl -fsSL "https://nodejs.org/dist/v$NODE/SHASUMS256.txt" | grep " $f\$" | sha256sum -c
    tar xJf "$f" -C /opt/node --strip-components=1

    f=fpm-${FPM:?}-linux-x86_64-gcc-12
    curl -fsSLO "$gh/fortran-lang/fpm/releases/download/v$FPM/$f"
    curl -fsSL "$gh/fortran-lang/fpm/releases/download/v$FPM/$f.sha256" | sha256sum -c
    install -m 755 "$f" /opt/tools/bin/fpm

    curl -fsSL "$gh/koalaman/shellcheck/releases/download/v${SHELLCHECK:?}/shellcheck-v$SHELLCHECK.linux.x86_64.tar.xz" \
      | tar xJ --strip-components=1 -C /opt/tools/bin "shellcheck-v$SHELLCHECK/shellcheck"

    curl -fsSL "$gh/fish-shell/fish-shell/releases/download/${FISH:?}/fish-$FISH-linux-x86_64.tar.xz" \
      | tar xJ -C /opt/tools/bin

    # PowerShell's hashes.sha256 is UTF-16LE with CRLF line ends
    f=powershell-${PWSH:?}-linux-x64.tar.gz
    curl -fsSLO "$gh/PowerShell/PowerShell/releases/download/v$PWSH/$f"
    curl -fsSL "$gh/PowerShell/PowerShell/releases/download/v$PWSH/hashes.sha256" \
      | iconv -f UTF-16 -t UTF-8 | tr -d '\r' | grep " \*$f\$" | sha256sum -c
    tar xzf "$f" -C /opt/pwsh && chmod +x /opt/pwsh/pwsh

    ln -s /opt/node/bin/node /opt/node/bin/npm /opt/node/bin/npx /opt/pwsh/pwsh /opt/tools/bin/
    ;;
  *) echo "install-tools.sh: unknown target $1" >&2; exit 2 ;;
esac
