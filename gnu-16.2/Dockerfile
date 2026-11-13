# Fortran toolchain gnu-16.2: gfortran 16.2.0, Open MPI 5.0.11, HDF5 2.3.0 (develop ab5df552: parallel, Fortran, static),
# all built by the same compiler, so every .mod file (mpi_f08, hdf5) is readable by the gfortran of the image. FoBiS and
# the Python build tools of the projects, FFTW. The same stack as the workstations (gcc/16.2.0, openmpi/5.0.11-gnu16.2.0,
# ADAM's lib/hdf5/develop/gnu/16.2.0), but HDF5 has the deflate filter (zlib) too.
#
#   docker build -t ghcr.io/szaghi/fortran-toolchains:gnu-16.2 gnu-16.2

ARG GCC_VERSION=16.2.0

# ---------------------------------------------------------------------------------------------------------------- build
FROM gcc:${GCC_VERSION} AS build

ARG OPENMPI_VERSION=5.0.11
ARG HDF5_COMMIT=ab5df5526c96a03bf1d89cea59603b77a239eac0
ARG JOBS=8

RUN apt-get update \
 && apt-get install -y --no-install-recommends cmake zlib1g-dev bzip2 ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Open MPI, with the Fortran bindings (mpi_f08) of this gfortran
RUN curl -fsSL https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-${OPENMPI_VERSION}.tar.bz2 | tar xj -C /tmp \
 && cd /tmp/openmpi-${OPENMPI_VERSION} \
 && ./configure --prefix=/opt/openmpi --enable-mpi-fortran=all --with-pmix=internal --with-hwloc=internal \
                --with-libevent=internal CC=gcc CXX=g++ FC=gfortran > /tmp/openmpi-configure.log \
 && make -j ${JOBS} > /tmp/openmpi-make.log \
 && make install > /dev/null \
 && rm -rf /tmp/openmpi-${OPENMPI_VERSION}
ENV PATH=/opt/openmpi/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/openmpi/lib

# HDF5: the commit of the workstations' builds, parallel, Fortran, high-level, static, deflate
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

# -------------------------------------------------------------------------------------------------------------- runtime
FROM gcc:${GCC_VERSION}

LABEL org.opencontainers.image.source=https://github.com/szaghi/fortran-toolchains \
      org.opencontainers.image.description="gfortran 16.2.0, Open MPI 5.0.11, HDF5 2.3.0 (parallel, Fortran), FoBiS"

RUN apt-get update \
 && apt-get install -y --no-install-recommends cmake zlib1g-dev liblz4-dev liblzma-dev libfftw3-dev pkg-config git make jq gawk python3 python3-venv \
                                               ca-certificates curl xz-utils bzip2 unzip \
 && rm -rf /var/lib/apt/lists/*

# every repository is safe: in a job container actions/checkout marks the workspace safe only in a temporary HOME, so
# any later git (the coverage outputs of ci.yml, the git diff checks) runs as root on a checkout owned by the runner
# user and dies with "detected dubious ownership"; checked below on a repository owned by another user
RUN git config --system --add safe.directory '*'

COPY --from=build /opt/openmpi /opt/openmpi
COPY --from=build /opt/hdf5 /opt/hdf5

# the Python tools of setup-build-env (FoBiS, ford, ...) in a venv: Debian's Python is externally managed
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir \
      markdown markdown-include python-markdown-math toposort jinja2 pygments beautifulsoup4 tqdm importlib-metadata \
      ford formal-ford2vitepress FoBiS.py gcovr

# containers run as root: Open MPI refuses it unless told, and the runners have few cores (oversubscribe)
ENV PATH=/opt/venv/bin:/opt/hdf5/bin:/opt/openmpi/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/openmpi/lib \
    HDF5_ROOT=/opt/hdf5 \
    OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    PRTE_MCA_rmaps_default_mapping_policy=:oversubscribe

# the toolchain, checked at build time: every .mod readable, MPI and HDF5 linked, 2 ranks run
COPY check.f90 /opt/toolchain/check.f90
RUN cd /tmp \
 && mpifort -I/opt/hdf5/include /opt/toolchain/check.f90 -o check \
            -L/opt/hdf5/lib -lhdf5_fortran -lhdf5_f90cstub -lhdf5 -lz -ldl -lm \
 && mpirun -np 2 ./check \
 && rm -f check *.h5 \
 && printf 'program p\nend program p\n' > lz.f90 && gfortran lz.f90 -o lz -llz4 -llzma && ./lz && rm -f lz lz.f90 \
 && git init -q /tmp/repo && chown -R 1001:1001 /tmp/repo && git -C /tmp/repo ls-files && rm -rf /tmp/repo \
 && gfortran --version | head -1 && mpifort --version | head -1 && mpirun --version | head -1 && fobis --version
