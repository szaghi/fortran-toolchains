# Fortran toolchain, GNU: gfortran, the Open MPI and HDF5 built by it (every .mod readable by the gfortran of the
# image), the tools of the projects' CI. The versions are build arguments, all from versions.env (the latest
# installed on the WSL box), and checked inside the image at build time. The recipes shared with the other vendors are
# the scripts of common/ (the build context is the repository root); scripts/build.sh passes the arguments:
#
#   scripts/build.sh gnu lite    # gfortran and the tools
#   scripts/build.sh gnu full    # + Open MPI, HDF5 (parallel, Fortran, static, deflate), FFTW 3, LZ4, LZMA
#   scripts/build.sh gnu gui     # + X11/Wayland development headers, Xvfb, Mesa (GUI programs without display or GPU)
#
# Every flavour checks itself while building: a broken image is never pushed.

ARG GCC

# ------------------------------------------------------------------------------------------------------------- tools
# CMake alone in its stage: the HDF5 build depends on it, and must not be rebuilt when another tool is bumped
FROM gcc:${GCC} AS cmake
ARG CMAKE
COPY common/install-tools.sh /tmp/install-tools.sh
RUN /tmp/install-tools.sh cmake

FROM gcc:${GCC} AS tools
ARG NINJA
ARG NODE
ARG FPM
ARG SHELLCHECK
ARG FISH
ARG PWSH
RUN apt-get update && apt-get install -y --no-install-recommends unzip xz-utils && rm -rf /var/lib/apt/lists/*
COPY common/install-tools.sh /tmp/install-tools.sh
RUN /tmp/install-tools.sh tools

# ---------------------------------------------------------------------------------------------------- build (MPI, HDF5)
FROM gcc:${GCC} AS build
ARG OPENMPI
ARG HDF5_COMMIT
ARG JOBS=8

RUN apt-get update \
 && apt-get install -y --no-install-recommends zlib1g-dev bzip2 ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Open MPI, with the Fortran bindings (mpi_f08) of this gfortran
RUN curl -fsSL https://download.open-mpi.org/release/open-mpi/v${OPENMPI%.*}/openmpi-${OPENMPI}.tar.bz2 | tar xj -C /tmp \
 && cd /tmp/openmpi-${OPENMPI} \
 && ./configure --prefix=/opt/openmpi --enable-mpi-fortran=all --with-pmix=internal --with-hwloc=internal \
                --with-libevent=internal CC=gcc CXX=g++ FC=gfortran > /tmp/openmpi-configure.log \
 && make -j ${JOBS} > /tmp/openmpi-make.log \
 && make install > /dev/null \
 && rm -rf /tmp/openmpi-${OPENMPI}
ENV PATH=/opt/openmpi/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/openmpi/lib

# HDF5 with the pinned CMake, copied here (after Open MPI, which does not use it) so a CMake bump does not rebuild Open MPI
COPY --from=cmake /opt/cmake /opt/cmake
ENV PATH=/opt/cmake/bin:${PATH}
COPY common/build-hdf5.sh /tmp/build-hdf5.sh
COPY common/hdf5-static-pc.sh /tmp/hdf5-static-pc.sh
RUN /tmp/build-hdf5.sh mpicc mpif90

# -------------------------------------------------------------------------------------------------------------- lite
# gfortran and the tools, no MPI nor HDF5
FROM gcc:${GCC} AS lite
ARG GCC
ARG TOOLCHAIN
ARG NODE
ARG FOBIS
ARG FORD
ARG FORMAL
ARG FPM
ARG CMAKE
ARG NINJA
ARG SHELLCHECK
ARG ZSH
ARG FISH
ARG PWSH
ARG NUMPY
ARG H5PY

LABEL org.opencontainers.image.source=https://github.com/szaghi/fortran-toolchains \
      org.opencontainers.image.description="gfortran ${GCC} and the CI tools (FoBiS, ford, formal, fpm, CMake, Node)"

COPY common/ /opt/toolchain/
RUN /opt/toolchain/install-base.sh lite
COPY --from=cmake /opt/cmake /opt/cmake
COPY --from=tools /opt/tools /opt/tools
COPY --from=tools /opt/node /opt/node
COPY --from=tools /opt/pwsh /opt/pwsh
RUN /opt/toolchain/install-venv.sh

ENV PATH=/opt/venv/bin:/opt/tools/bin:/opt/cmake/bin:${PATH}

# the environment contract of every toolchain (common/check-contract.sh): the C side is the distribution's gcc/g++
ENV FC=gfortran \
    CC=gcc \
    CXX=g++ \
    TOOLCHAIN=${TOOLCHAIN} \
    TOOLCHAIN_OS=linux \
    TOOLCHAIN_FAMILY=gnu

RUN /opt/toolchain/check-versions.sh GCC NODE FOBIS FORD FORMAL FPM CMAKE NINJA SHELLCHECK ZSH FISH PWSH NUMPY H5PY \
 && /opt/toolchain/check-image.sh lite \
 && /opt/toolchain/check-contract.sh

# -------------------------------------------------------------------------------------------------------------- full
# + Open MPI, HDF5, FFTW 3, LZ4, LZMA
FROM lite AS full
ARG GCC
ARG OPENMPI
ARG HDF5

LABEL org.opencontainers.image.description="gfortran ${GCC}, Open MPI ${OPENMPI}, HDF5 (parallel, Fortran), FoBiS"

RUN /opt/toolchain/install-base.sh full
COPY --from=build /opt/openmpi /opt/openmpi
COPY --from=build /opt/hdf5 /opt/hdf5

# containers run as root: Open MPI refuses it unless told, and the runners have few cores (oversubscribe)
ENV PATH=/opt/hdf5/bin:/opt/openmpi/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/openmpi/lib \
    HDF5_ROOT=/opt/hdf5 \
    PKG_CONFIG_PATH=/opt/hdf5/lib/pkgconfig \
    OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    PRTE_MCA_rmaps_default_mapping_policy=:oversubscribe \
    MPIFC=mpifort \
    MPIRUN=mpirun

RUN /opt/toolchain/check-image.sh full mpifort \
 && /opt/toolchain/check-versions.sh OPENMPI HDF5 \
 && /opt/toolchain/check-contract.sh --mpi

# --------------------------------------------------------------------------------------------------------------- gui
# + what GUI programs need to build and run without a display or a GPU
FROM full AS gui
ARG GCC

LABEL org.opencontainers.image.description="gfortran ${GCC}, Open MPI, HDF5, FoBiS; X11/Wayland headers, Xvfb, Mesa"

RUN /opt/toolchain/install-base.sh gui \
 && /opt/toolchain/check-image.sh gui
