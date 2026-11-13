# Fortran toolchain, Intel oneAPI: ifx and Intel MPI from Intel's apt repository, HDF5 built by them, the tools of the
# projects' CI. The versions are build arguments, all from versions.env (the latest installed on the WSL box), and
# checked inside the image at build time; the recipes shared with the other vendors are the scripts of common/:
#
#   scripts/build.sh oneapi lite    # ifx and the tools
#   scripts/build.sh oneapi full    # + Intel MPI, HDF5 (parallel, Fortran, static, deflate), FFTW 3, LZ4, LZMA
#   scripts/build.sh oneapi gui     # + X11/Wayland development headers, Xvfb, Mesa
#
# The C side is the distribution's gcc (Intel MPI's mpicc wraps it; ifx links through it), as on the WSL box.

ARG UBUNTU

# ------------------------------------------------------------------------------------------------------------- tools
FROM ubuntu:${UBUNTU} AS cmake
ARG CMAKE
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY common/install-tools.sh /tmp/install-tools.sh
RUN /tmp/install-tools.sh cmake

FROM ubuntu:${UBUNTU} AS tools
ARG NINJA
ARG NODE
ARG FPM
ARG SHELLCHECK
ARG FISH
ARG PWSH
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
COPY common/install-tools.sh /tmp/install-tools.sh
RUN /tmp/install-tools.sh tools

# ------------------------------------------------------------------------------------------------------------- oneapi
# ifx and Intel MPI at the exact WSL versions (apt would take the newest patch release of a series otherwise);
# lite has the MPI runtime only because ifx's package depends on it
FROM ubuntu:${UBUNTU} AS oneapi
ARG IFX
ARG INTEL_MPI
COPY common/install-base.sh /opt/toolchain/install-base.sh
RUN /opt/toolchain/install-base.sh lite \
 && export DEBIAN_FRONTEND=noninteractive \
 && apt-get update && apt-get install -y --no-install-recommends gnupg gcc g++ \
 && curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
      | gpg --dearmor -o /usr/share/keyrings/oneapi-archive-keyring.gpg \
 && echo 'deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main' \
      > /etc/apt/sources.list.d/oneAPI.list \
 && apt-get update \
 && fortran=intel-oneapi-compiler-fortran-${IFX%.*} \
 && v_fortran=$(apt-cache madison "$fortran" | awk '{print $3}' | grep -E "^${IFX}-" | head -1) \
 && mpi=intel-oneapi-mpi-${INTEL_MPI%.*} \
 && v_mpi=$(apt-cache madison "$mpi" | awk '{print $3}' | grep -E "^${INTEL_MPI}-" | head -1) \
 && echo "ifx: $fortran=$v_fortran, Intel MPI: $mpi=$v_mpi" && test -n "$v_fortran" && test -n "$v_mpi" \
 && apt-get install -y --no-install-recommends "$fortran=$v_fortran" "$mpi=$v_mpi" \
 && rm -rf /var/lib/apt/lists/*

# the environment of compiler/latest/env/vars.sh and mpi/latest/env/vars.sh (no shell sources them in a CI step)
ENV CMPLR_ROOT=/opt/intel/oneapi/compiler/latest \
    I_MPI_ROOT=/opt/intel/oneapi/mpi/latest
ENV PATH=${I_MPI_ROOT}/bin:${CMPLR_ROOT}/bin:${PATH} \
    LD_LIBRARY_PATH=${I_MPI_ROOT}/lib:${CMPLR_ROOT}/opt/compiler/lib:${CMPLR_ROOT}/lib \
    LIBRARY_PATH=${I_MPI_ROOT}/lib:${CMPLR_ROOT}/lib \
    C_INCLUDE_PATH=${I_MPI_ROOT}/include \
    CPLUS_INCLUDE_PATH=${I_MPI_ROOT}/include \
    PKG_CONFIG_PATH=${I_MPI_ROOT}/lib/pkgconfig:${CMPLR_ROOT}/lib/pkgconfig \
    CMAKE_PREFIX_PATH=${CMPLR_ROOT} \
    NLSPATH=${CMPLR_ROOT}/lib/compiler/locale/%l_%t/%N

# ---------------------------------------------------------------------------------------------------- build (HDF5)
FROM oneapi AS build
ARG INTEL_MPI
ARG HDF5_COMMIT
ARG JOBS=8
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update \
 && v=$(apt-cache madison intel-oneapi-mpi-devel-${INTEL_MPI%.*} | awk '{print $3}' | grep -E "^${INTEL_MPI}-" | head -1) \
 && apt-get install -y --no-install-recommends "intel-oneapi-mpi-devel-${INTEL_MPI%.*}=$v" zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*
COPY --from=cmake /opt/cmake /opt/cmake
ENV PATH=/opt/cmake/bin:${PATH}
COPY common/build-hdf5.sh /tmp/build-hdf5.sh
RUN /tmp/build-hdf5.sh mpicc mpiifx

# -------------------------------------------------------------------------------------------------------------- lite
FROM oneapi AS lite
ARG UBUNTU
ARG TOOLCHAIN
ARG IFX
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
      org.opencontainers.image.description="Intel ifx ${IFX} and the CI tools (FoBiS, ford, formal, fpm, CMake, Node)"

COPY common/ /opt/toolchain/
COPY --from=cmake /opt/cmake /opt/cmake
COPY --from=tools /opt/tools /opt/tools
COPY --from=tools /opt/node /opt/node
COPY --from=tools /opt/pwsh /opt/pwsh
RUN /opt/toolchain/install-venv.sh

ENV PATH=/opt/venv/bin:/opt/tools/bin:/opt/cmake/bin:${PATH}

# the environment contract of every toolchain (common/check-contract.sh): the C side is the distribution's gcc/g++
ENV FC=ifx \
    CC=gcc \
    CXX=g++ \
    TOOLCHAIN=${TOOLCHAIN} \
    TOOLCHAIN_OS=linux \
    TOOLCHAIN_FAMILY=intel

RUN /opt/toolchain/check-versions.sh UBUNTU IFX NODE FOBIS FORD FORMAL FPM CMAKE NINJA SHELLCHECK ZSH FISH PWSH NUMPY H5PY \
 && /opt/toolchain/check-image.sh lite \
 && /opt/toolchain/check-contract.sh

# -------------------------------------------------------------------------------------------------------------- full
# + the Intel MPI development files, HDF5, FFTW 3, LZ4, LZMA
FROM lite AS full
ARG IFX
ARG INTEL_MPI
ARG HDF5

LABEL org.opencontainers.image.description="Intel ifx ${IFX}, Intel MPI ${INTEL_MPI}, HDF5 (parallel, Fortran), FoBiS"

RUN /opt/toolchain/install-base.sh full \
 && export DEBIAN_FRONTEND=noninteractive && apt-get update \
 && v=$(apt-cache madison intel-oneapi-mpi-devel-${INTEL_MPI%.*} | awk '{print $3}' | grep -E "^${INTEL_MPI}-" | head -1) \
 && apt-get install -y --no-install-recommends "intel-oneapi-mpi-devel-${INTEL_MPI%.*}=$v" \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /opt/hdf5 /opt/hdf5

ENV PATH=/opt/hdf5/bin:${PATH} \
    HDF5_ROOT=/opt/hdf5 \
    MPIFC=mpiifx \
    MPIRUN=mpirun

RUN /opt/toolchain/check-image.sh full mpiifx \
 && /opt/toolchain/check-versions.sh INTEL_MPI HDF5 \
 && /opt/toolchain/check-contract.sh --mpi

# --------------------------------------------------------------------------------------------------------------- gui
FROM full AS gui
ARG IFX

LABEL org.opencontainers.image.description="Intel ifx ${IFX}, Intel MPI, HDF5, FoBiS; X11/Wayland headers, Xvfb, Mesa"

RUN /opt/toolchain/install-base.sh gui \
 && /opt/toolchain/check-image.sh gui
