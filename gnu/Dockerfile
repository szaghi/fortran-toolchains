# Fortran toolchain, GNU: gfortran, the Open MPI and HDF5 built by it (every .mod readable by the gfortran of the
# image), the tools of the projects' CI. The versions are build arguments, all from versions.env (the latest
# installed on the WSL box), and checked inside the image at build time (common/check-versions.sh). The build
# context is the repository root; scripts/build.sh passes the arguments:
#
#   scripts/build.sh gnu lite    # gfortran and the tools
#   scripts/build.sh gnu full    # + Open MPI, HDF5 (parallel, Fortran, static, deflate), FFTW 3, LZ4, LZMA
#
# Every flavour checks itself while building: a broken image is never pushed.

ARG GCC

# ------------------------------------------------------------------------------------------------------------- tools
# release binaries of the tools, at the WSL versions. Checksums verified where upstream publishes them (CMake, Node,
# fpm, PowerShell: its hashes.sha256 is UTF-16 with CRLF); ninja, ShellCheck and fish publish none.
# CMake alone in its stage: the MPI/HDF5 build depends on it, and must not be rebuilt when another tool is bumped
FROM gcc:${GCC} AS cmake
ARG CMAKE
WORKDIR /tmp/cmake
RUN curl -fsSLO https://github.com/Kitware/CMake/releases/download/v${CMAKE}/cmake-${CMAKE}-linux-x86_64.tar.gz \
 && curl -fsSL https://github.com/Kitware/CMake/releases/download/v${CMAKE}/cmake-${CMAKE}-SHA-256.txt \
      | grep " cmake-${CMAKE}-linux-x86_64.tar.gz$" | sha256sum -c \
 && mkdir -p /opt/cmake && tar xzf cmake-${CMAKE}-linux-x86_64.tar.gz -C /opt/cmake --strip-components=1 \
 && rm cmake-${CMAKE}-linux-x86_64.tar.gz

# the other tools in /opt/tools (bin/ on PATH), Node in /opt/node, PowerShell in /opt/pwsh
FROM gcc:${GCC} AS tools
ARG NINJA
ARG NODE
ARG FPM
ARG SHELLCHECK
ARG FISH
ARG PWSH
RUN apt-get update && apt-get install -y --no-install-recommends unzip xz-utils && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp/tools
RUN mkdir -p /opt/tools/bin \
 && curl -fsSLO https://github.com/ninja-build/ninja/releases/download/v${NINJA}/ninja-linux.zip \
 && unzip -q ninja-linux.zip -d /opt/tools/bin && rm ninja-linux.zip \
 && curl -fsSLO https://nodejs.org/dist/v${NODE}/node-v${NODE}-linux-x64.tar.xz \
 && curl -fsSL https://nodejs.org/dist/v${NODE}/SHASUMS256.txt | grep " node-v${NODE}-linux-x64.tar.xz$" | sha256sum -c \
 && mkdir -p /opt/node && tar xJf node-v${NODE}-linux-x64.tar.xz -C /opt/node --strip-components=1 \
 && rm node-v${NODE}-linux-x64.tar.xz \
 && curl -fsSLO https://github.com/fortran-lang/fpm/releases/download/v${FPM}/fpm-${FPM}-linux-x86_64-gcc-12 \
 && curl -fsSL https://github.com/fortran-lang/fpm/releases/download/v${FPM}/fpm-${FPM}-linux-x86_64-gcc-12.sha256 \
      | sha256sum -c \
 && install -m 755 fpm-${FPM}-linux-x86_64-gcc-12 /opt/tools/bin/fpm && rm fpm-${FPM}-linux-x86_64-gcc-12* \
 && curl -fsSL https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK}/shellcheck-v${SHELLCHECK}.linux.x86_64.tar.xz \
      | tar xJ --strip-components=1 -C /opt/tools/bin shellcheck-v${SHELLCHECK}/shellcheck \
 && curl -fsSL https://github.com/fish-shell/fish-shell/releases/download/${FISH}/fish-${FISH}-linux-x86_64.tar.xz \
      | tar xJ -C /opt/tools/bin \
 && curl -fsSLO https://github.com/PowerShell/PowerShell/releases/download/v${PWSH}/powershell-${PWSH}-linux-x64.tar.gz \
 && curl -fsSL https://github.com/PowerShell/PowerShell/releases/download/v${PWSH}/hashes.sha256 \
      | iconv -f UTF-16 -t UTF-8 | tr -d '\r' | grep " \*powershell-${PWSH}-linux-x64.tar.gz$" | sha256sum -c \
 && mkdir -p /opt/pwsh && tar xzf powershell-${PWSH}-linux-x64.tar.gz -C /opt/pwsh && chmod +x /opt/pwsh/pwsh \
 && rm powershell-${PWSH}-linux-x64.tar.gz

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

# HDF5: the commit of the workstations' builds, parallel, Fortran, high-level, static, deflate; configured with the
# pinned CMake, copied here (after Open MPI, which does not use it) so a CMake bump does not rebuild Open MPI
COPY --from=cmake /opt/cmake /opt/cmake
ENV PATH=/opt/cmake/bin:${PATH}
RUN curl -fsSL https://github.com/HDFGroup/hdf5/archive/${HDF5_COMMIT}.tar.gz | tar xz -C /tmp \
 && cmake -S /tmp/hdf5-${HDF5_COMMIT} -B /tmp/hdf5-build \
          -DCMAKE_INSTALL_PREFIX=/opt/hdf5 -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_C_COMPILER=mpicc -DCMAKE_Fortran_COMPILER=mpif90 \
          -DCMAKE_C_FLAGS=-fPIC -DCMAKE_Fortran_FLAGS=-fPIC \
          -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_TESTING=OFF \
          -DHDF5_ENABLE_PARALLEL=ON -DHDF5_BUILD_FORTRAN=ON -DHDF5_BUILD_HL_LIB=ON -DHDF5_BUILD_CPP_LIB=OFF \
          -DHDF5_BUILD_JAVA=OFF -DHDF5_BUILD_EXAMPLES=OFF -DHDF5_BUILD_TOOLS=ON \
          -DHDF5_ENABLE_ZLIB_SUPPORT=ON -DHDF5_ENABLE_SZIP_SUPPORT=OFF > /tmp/hdf5-configure.log \
 && cmake --build /tmp/hdf5-build -j ${JOBS} > /tmp/hdf5-build.log \
 && cmake --install /tmp/hdf5-build > /dev/null \
 && grep -E 'Parallel HDF5|Fortran: |I/O filters' /opt/hdf5/lib/libhdf5.settings \
 && rm -rf /tmp/hdf5-${HDF5_COMMIT} /tmp/hdf5-build

# -------------------------------------------------------------------------------------------------------------- lite
# gfortran and the tools, no MPI nor HDF5
FROM gcc:${GCC} AS lite
ARG GCC
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

# zsh from Debian (trixie has the WSL version, checked below); libicu for PowerShell
RUN apt-get update \
 && apt-get install -y --no-install-recommends pkg-config git make jq gawk python3 python3-venv zsh libicu76 \
                                               ca-certificates curl xz-utils bzip2 unzip \
 && rm -rf /var/lib/apt/lists/*

# every repository is safe: in a job container actions/checkout marks the workspace safe only in a temporary HOME, so
# any later git (the coverage outputs of ci.yml, the git diff checks) runs as root on a checkout owned by the runner
# user and dies with "detected dubious ownership"; checked below on a repository owned by another user
RUN git config --system --add safe.directory '*'

COPY --from=cmake /opt/cmake /opt/cmake
COPY --from=tools /opt/tools /opt/tools
COPY --from=tools /opt/node /opt/node
COPY --from=tools /opt/pwsh /opt/pwsh
RUN ln -s /opt/node/bin/node /opt/node/bin/npm /opt/node/bin/npx /opt/pwsh/pwsh /opt/tools/bin/

# the Python tools in a venv (Debian's Python is externally managed), pinned to the WSL versions; the Markdown
# extensions are those the projects' ford.md files name; numpy and h5py for regression oracles (ADAM)
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir \
      "FoBiS.py==${FOBIS}" "ford==${FORD}" "formal-ford2vitepress==${FORMAL}" "numpy==${NUMPY}" "h5py==${H5PY}" \
      markdown markdown-include python-markdown-math toposort jinja2 pygments beautifulsoup4 tqdm importlib-metadata

ENV PATH=/opt/venv/bin:/opt/tools/bin:/opt/cmake/bin:${PATH}

# every tool at its pin, git on a repository owned by another user
COPY common/check-versions.sh /opt/toolchain/check-versions.sh
RUN /opt/toolchain/check-versions.sh GCC NODE FOBIS FORD FORMAL FPM CMAKE NINJA SHELLCHECK ZSH FISH PWSH NUMPY H5PY \
 && git init -q /tmp/repo && chown -R 1001:1001 /tmp/repo && git -C /tmp/repo ls-files && rm -rf /tmp/repo

# -------------------------------------------------------------------------------------------------------------- full
# + Open MPI, HDF5, FFTW 3, LZ4, LZMA
FROM lite AS full
ARG GCC
ARG OPENMPI
ARG HDF5

LABEL org.opencontainers.image.description="gfortran ${GCC}, Open MPI ${OPENMPI}, HDF5 (parallel, Fortran), FoBiS"

RUN apt-get update \
 && apt-get install -y --no-install-recommends zlib1g-dev liblz4-dev liblzma-dev libfftw3-dev \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/openmpi /opt/openmpi
COPY --from=build /opt/hdf5 /opt/hdf5

# containers run as root: Open MPI refuses it unless told, and the runners have few cores (oversubscribe)
ENV PATH=/opt/hdf5/bin:/opt/openmpi/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/openmpi/lib \
    HDF5_ROOT=/opt/hdf5 \
    OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    PRTE_MCA_rmaps_default_mapping_policy=:oversubscribe

# the toolchain, checked at build time: every .mod readable, MPI and HDF5 linked, 2 ranks run; LZ4 and LZMA linkable
COPY gnu/check.f90 /opt/toolchain/check.f90
RUN cd /tmp \
 && mpifort -I/opt/hdf5/include /opt/toolchain/check.f90 -o check \
            -L/opt/hdf5/lib -lhdf5_fortran -lhdf5_f90cstub -lhdf5 -lz -ldl -lm \
 && mpirun -np 2 ./check \
 && rm -f check *.h5 \
 && printf 'program p\nend program p\n' > lz.f90 && gfortran lz.f90 -o lz -llz4 -llzma && ./lz && rm -f lz lz.f90 \
 && /opt/toolchain/check-versions.sh OPENMPI HDF5
