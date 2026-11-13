#!/usr/bin/env bash
# Run inside an image at build time (a failure fails the build, so a broken image is never pushed):
#
#   check-image.sh lite                git works on a repository owned by another user (a job container's checkout)
#   check-image.sh full <mpifort>      check.f90 built by <mpifort> against /opt/hdf5 and run on 2 ranks (mpi_f08 and
#                                      hdf5 modules readable, a parallel HDF5 file written collectively, the deflate
#                                      filter); a program linked against LZ4 and LZMA
#   check-image.sh gui                 an X server under Xvfb (24-bit) whose OpenGL is Mesa's llvmpipe
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d); cd "$work"
trap 'rm -rf "$work"' EXIT

case ${1:?usage: check-image.sh lite|full <mpifort>|gui} in
  lite)
    git init -q repo && chown -R 1001:1001 repo && git -C repo ls-files
    ;;
  full)
    fc=${2:?usage: check-image.sh full <mpifort>}
    "$fc" -I/opt/hdf5/include "$here/check.f90" -o check \
          -L/opt/hdf5/lib -lhdf5_fortran -lhdf5_f90cstub -lhdf5 -lz -ldl -lm
    mpirun -np 2 ./check
    printf 'program p\nend program p\n' > lz.f90 && "$fc" lz.f90 -o lz -llz4 -llzma && ./lz
    ;;
  gui)
    xvfb-run -a -s "-screen 0 1280x1024x24" glxinfo -B > glx.txt
    grep -E 'OpenGL renderer|OpenGL core profile version' glx.txt
    grep -q llvmpipe glx.txt
    ;;
  *) echo "check-image.sh: unknown flavour $1" >&2; exit 2 ;;
esac
