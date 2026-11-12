# fortran-toolchains

Container images of the Fortran toolchains used to build and test my projects, in CI and anywhere else: each image is
one compiler with the MPI and HDF5 built by it, so every Fortran module file (`mpi_f08`, `hdf5`) is readable by the
compiler of the image.

| Image | Compiler | MPI | HDF5 | Tools |
|---|---|---|---|---|
| `ghcr.io/szaghi/fortran-toolchains:gnu-16.2` | gfortran 16.2.0 (official `gcc:16.2.0`, Debian trixie) | Open MPI 5.0.11 (`mpi_f08`) | 2.3.0, develop `ab5df552`: parallel, Fortran, high-level, static, deflate | FoBiS, ford, formal, gcovr, CMake, git, jq, GNU awk; zlib, FFTW 3 |

The same stack as the workstations (Lmod `gcc/16.2.0`, `openmpi/5.0.11-gnu16.2.0`, ADAM's `lib/hdf5/develop/gnu/16.2.0`),
but HDF5 has the deflate filter. Each image is also tagged with its build date (`gnu-16.2-20261111`) to pin a build.

## Use in GitHub Actions

```yaml
jobs:
  test:
    runs-on: ubuntu-24.04
    container: ghcr.io/szaghi/fortran-toolchains:gnu-16.2
    steps:
    - uses: actions/checkout@v5
    - run: fobis fetch && fobis build --mode tests-gnu-debug && bash scripts/run_tests.sh
```

Nothing is installed when the job runs. The image sets:

- `PATH`: the compilers, `mpifort`/`mpicc`/`mpirun`, the HDF5 tools, the Python tools (venv `/opt/venv`);
- `HDF5_ROOT=/opt/hdf5` (CMake's `find_package(HDF5)`); a FoBiS varset points at `/opt/hdf5/lib` and `/opt/hdf5/include`
  (static libraries: link `hdf5_fortran hdf5_f90cstub hdf5 z dl m`);
- `OMPI_ALLOW_RUN_AS_ROOT=1`, `OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1` (containers run as root) and oversubscription by default
  (`mpirun -np 4` on a 2-core runner);
- git `safe.directory = *` (system config): `actions/checkout` marks the workspace safe only in a temporary `HOME`, so
  without it every later `git` of the job dies with "detected dubious ownership" (root on a checkout owned by the runner
  user).

## Locally

```bash
docker run --rm -it -v $PWD:/work -w /work ghcr.io/szaghi/fortran-toolchains:gnu-16.2 bash
```

A CI failure is reproduced with the same image, the same toolchain.

## Build

`docker build -t ghcr.io/szaghi/fortran-toolchains:gnu-16.2 gnu-16.2` (about 30 minutes: Open MPI and HDF5 are built from
source). The *Build* workflow builds and pushes an image when its directory changes; the image checks its toolchain while
building (`check.f90`: `mpi_f08` and `hdf5` modules, a parallel HDF5 file written by 2 ranks, the deflate filter), so a
broken toolchain is never pushed.

A new toolchain is a new directory (`gnu-17.1`, `nvhpc-26.9`, ...) and a matrix entry of the workflow; the projects move
by changing the image tag in their workflows (through the FoBiS scaffold templates).
