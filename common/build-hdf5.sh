#!/usr/bin/env bash
# HDF5 at the commit of the workstations' builds ($HDF5_COMMIT), built by the image's MPI compiler wrappers into
# $HDF5_PREFIX (default /opt/hdf5; the macOS setup builds into its own prefix): parallel, Fortran, high-level, tools,
# static only (-fPIC), deflate on (zlib), szip off. The same recipe as ADAM's lib/hdf5/develop/<compiler>/<version>
# builds, plus deflate. Its pkg-config files carry the static link line (hdf5-static-pc.sh). Needs cmake on PATH; works
# in $TMPDIR (default /tmp).
#
#   build-hdf5.sh <mpi C wrapper> <mpi Fortran wrapper>      e.g. build-hdf5.sh mpicc mpif90
set -euo pipefail
cc=${1:?usage: build-hdf5.sh <mpicc> <mpifort>} fc=${2:?usage: build-hdf5.sh <mpicc> <mpifort>}

prefix=${HDF5_PREFIX:-/opt/hdf5} tmp=${TMPDIR:-/tmp}
src=$tmp/hdf5-${HDF5_COMMIT:?} build=$tmp/hdf5-build
curl -fsSL "https://github.com/HDFGroup/hdf5/archive/$HDF5_COMMIT.tar.gz" | tar xz -C "$tmp"
cmake -S "$src" -B "$build" \
      -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER="$cc" -DCMAKE_Fortran_COMPILER="$fc" \
      -DCMAKE_C_FLAGS=-fPIC -DCMAKE_Fortran_FLAGS=-fPIC \
      -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_TESTING=OFF \
      -DHDF5_ENABLE_PARALLEL=ON -DHDF5_BUILD_FORTRAN=ON -DHDF5_BUILD_HL_LIB=ON -DHDF5_BUILD_CPP_LIB=OFF \
      -DHDF5_BUILD_JAVA=OFF -DHDF5_BUILD_EXAMPLES=OFF -DHDF5_BUILD_TOOLS=ON \
      -DHDF5_ENABLE_ZLIB_SUPPORT=ON -DHDF5_ENABLE_SZIP_SUPPORT=OFF > "$tmp/hdf5-configure.log" \
  || { tail -40 "$tmp/hdf5-configure.log"; exit 1; }
cmake --build "$build" -j "${JOBS:-8}" > "$tmp/hdf5-build.log" || { tail -40 "$tmp/hdf5-build.log"; exit 1; }
cmake --install "$build" > /dev/null
"$(dirname "${BASH_SOURCE[0]}")/hdf5-static-pc.sh" "$prefix"
grep -E 'Parallel HDF5|Fortran: |Fortran Compiler|I/O filters' "$prefix/lib/libhdf5.settings"
rm -rf "$src" "$build"
