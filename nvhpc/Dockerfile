# Fortran toolchain, NVIDIA HPC SDK: nvfortran, its bundled HPC-X Open MPI and CUDA, HDF5 built by them, the tools of
# the projects' CI. The versions are build arguments, all from versions.env (the latest installed on the WSL box), and
# checked inside the image at build time; the recipes shared with the other vendors are the scripts of common/:
#
#   scripts/build.sh nvhpc lite    # nvfortran (SDK with HPC-X, CUDA, math libraries) and the tools
#   scripts/build.sh nvhpc full    # + HDF5 (parallel, Fortran, static, deflate), FFTW 3, LZ4, LZMA
#   scripts/build.sh nvhpc gui     # + X11/Wayland development headers, Xvfb, Mesa
#
# Compile and CPU runs only: the hosted runners have no GPU. The SDK is trimmed of what neither needs (profilers,
# examples, NCCL, NVSHMEM, CUDA forward compatibility, static math libraries): 15 GB installed, about 7 GB kept.

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

# -------------------------------------------------------------------------------------------------------------- sdk
# the SDK from NVIDIA's apt repository at the exact WSL version, installed and trimmed in one layer
FROM ubuntu:${UBUNTU} AS sdk
ARG NVHPC
ARG CUDA
COPY common/install-base.sh /opt/toolchain/install-base.sh
RUN /opt/toolchain/install-base.sh lite \
 && export DEBIAN_FRONTEND=noninteractive \
 && apt-get update && apt-get install -y --no-install-recommends gnupg \
 && curl -fsSL https://developer.download.nvidia.com/hpc-sdk/ubuntu/DEB-GPG-KEY-NVIDIA-HPC-SDK \
      | gpg --dearmor -o /usr/share/keyrings/nvidia-hpcsdk-archive-keyring.gpg \
 && echo 'deb [signed-by=/usr/share/keyrings/nvidia-hpcsdk-archive-keyring.gpg] https://developer.download.nvidia.com/hpc-sdk/ubuntu/amd64 /' \
      > /etc/apt/sources.list.d/nvhpc.list \
 && apt-get update \
 && sdk=nvhpc-$(echo "$NVHPC" | tr . -) \
 && v=$(apt-cache madison "$sdk" | awk '{print $3}' | grep -E "^${NVHPC}-" | head -1) \
 && echo "NVIDIA HPC SDK: $sdk=$v" && test -n "$v" \
 && apt-get install -y --no-install-recommends "$sdk=$v" \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && r=/opt/nvidia/hpc_sdk/Linux_x86_64/${NVHPC} \
 && test -d "$r/cuda/${CUDA}" \
 && du -sh "$r" \
 && rm -rf "$r/profilers" "$r/examples" "$r/comm_libs/${CUDA}/nccl" "$r/comm_libs/${CUDA}/nvshmem" \
           "$r/comm_libs/nccl" "$r/comm_libs/nvshmem" "$r/cuda/${CUDA}/compat" \
 && find "$r/math_libs" -name '*_static.a' -delete \
 && du -sh "$r"

# the environment of the SDK's nvhpc modulefile (no shell loads it in a CI step), less NCCL and NVSHMEM; containers run
# as root: HPC-X's Open MPI (5.0) refuses it unless told, and the runners have few cores (oversubscribe)
ENV NVHPC_ROOT=/opt/nvidia/hpc_sdk/Linux_x86_64/${NVHPC}
ENV PATH=${NVHPC_ROOT}/comm_libs/mpi/bin:${NVHPC_ROOT}/compilers/bin:${NVHPC_ROOT}/cuda/bin:${NVHPC_ROOT}/compilers/extras/qd/bin:${PATH} \
    LD_LIBRARY_PATH=${NVHPC_ROOT}/math_libs/lib64:${NVHPC_ROOT}/compilers/lib:${NVHPC_ROOT}/compilers/extras/qd/lib:${NVHPC_ROOT}/cuda/lib64 \
    CPATH=${NVHPC_ROOT}/compilers/extras/qd/include/qd:${NVHPC_ROOT}/math_libs/include \
    OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    PRTE_MCA_rmaps_default_mapping_policy=:oversubscribe

# ---------------------------------------------------------------------------------------------------- build (HDF5)
FROM sdk AS build
ARG HDF5_COMMIT
ARG JOBS=8
RUN apt-get update && apt-get install -y --no-install-recommends zlib1g-dev && rm -rf /var/lib/apt/lists/*
COPY --from=cmake /opt/cmake /opt/cmake
ENV PATH=/opt/cmake/bin:${PATH}
COPY common/build-hdf5.sh /tmp/build-hdf5.sh
COPY common/hdf5-static-pc.sh /tmp/hdf5-static-pc.sh
RUN HDF5_ARCH_FLAGS=-tp=px /tmp/build-hdf5.sh mpicc mpifort

# -------------------------------------------------------------------------------------------------------------- lite
FROM sdk AS lite
ARG UBUNTU
ARG TOOLCHAIN
ARG NVHPC
ARG CUDA
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
      org.opencontainers.image.description="nvfortran ${NVHPC} (CUDA ${CUDA}, HPC-X) and the CI tools (FoBiS, ford, formal, fpm, CMake, Node)"

COPY common/ /opt/toolchain/
COPY --from=cmake /opt/cmake /opt/cmake
COPY --from=tools /opt/tools /opt/tools
COPY --from=tools /opt/node /opt/node
COPY --from=tools /opt/pwsh /opt/pwsh
RUN /opt/toolchain/install-venv.sh

ENV PATH=/opt/venv/bin:/opt/tools/bin:/opt/cmake/bin:${PATH}

# the environment contract of every toolchain (common/check-contract.sh): the C side is the distribution's gcc/g++
ENV FC=nvfortran \
    CC=gcc \
    CXX=g++ \
    TOOLCHAIN=${TOOLCHAIN} \
    TOOLCHAIN_OS=linux \
    TOOLCHAIN_FAMILY=nvf

RUN /opt/toolchain/check-versions.sh UBUNTU NVHPC CUDA NODE FOBIS FORD FORMAL FPM CMAKE NINJA SHELLCHECK ZSH FISH PWSH NUMPY H5PY \
 && /opt/toolchain/check-image.sh lite \
 && /opt/toolchain/check-contract.sh

# -------------------------------------------------------------------------------------------------------------- full
FROM lite AS full
ARG NVHPC
ARG HDF5

LABEL org.opencontainers.image.description="nvfortran ${NVHPC}, HPC-X Open MPI, HDF5 (parallel, Fortran), FoBiS"

RUN /opt/toolchain/install-base.sh full
COPY --from=build /opt/hdf5 /opt/hdf5

ENV PATH=/opt/hdf5/bin:${PATH} \
    HDF5_ROOT=/opt/hdf5 \
    PKG_CONFIG_PATH=/opt/hdf5/lib/pkgconfig \
    MPIFC=mpifort \
    MPIRUN=mpirun

RUN /opt/toolchain/check-image.sh full mpifort \
 && /opt/toolchain/check-versions.sh HDF5 \
 && /opt/toolchain/check-contract.sh --mpi

# --------------------------------------------------------------------------------------------------------------- gui
FROM full AS gui
ARG NVHPC

LABEL org.opencontainers.image.description="nvfortran ${NVHPC}, HPC-X, HDF5, FoBiS; X11/Wayland headers, Xvfb, Mesa"

RUN /opt/toolchain/install-base.sh gui \
 && /opt/toolchain/check-image.sh gui
