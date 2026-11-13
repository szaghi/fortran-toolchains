# fortran-toolchains

Container images of the Fortran toolchains used to build and test my projects, in CI and anywhere else: each image is
one compiler with the MPI and HDF5 built by it, so every Fortran module file (`mpi_f08`, `hdf5`) is readable by the
compiler of the image. Every version is the latest installed on my development machine (`versions.env`), and the
images check it while building. The plan (more vendors, macOS/Windows setups, reusable workflows) is in
[ROADMAP.md](ROADMAP.md).

| Image | Contents |
|---|---|
| `ghcr.io/szaghi/fortran-toolchains:gnu-16.2` | gfortran 16.2.0 (official `gcc:16.2.0`, Debian trixie); Open MPI 5.0.11 (`mpi_f08`); HDF5 2.3.0, develop `ab5df552`: parallel, Fortran, high-level, static, deflate; zlib, LZ4, LZMA, FFTW 3; the tools |
| `ghcr.io/szaghi/fortran-toolchains:gnu-16.2-lite` | gfortran 16.2.0 and the tools: no MPI, no HDF5 |
| `ghcr.io/szaghi/fortran-toolchains:gnu-16.2-gui` | `gnu-16.2` + the X11/Wayland development headers (SDL), Xvfb (`xvfb-run`), Mesa llvmpipe (OpenGL without a GPU) |
| `ghcr.io/szaghi/fortran-toolchains:nvhpc-26.9` | nvfortran 26.9 (NVIDIA HPC SDK, Ubuntu 24.04), its HPC-X Open MPI 5.0 and CUDA 13.3, math libraries (cuFFT, cuBLAS, ...); HDF5 2.3.0 built by nvfortran; zlib, LZ4, LZMA, FFTW 3; the tools. Compile and CPU runs: the hosted runners have no GPU. Also `-lite` (no HDF5), `-gui` |
| `ghcr.io/szaghi/fortran-toolchains:oneapi-2026.2` | Intel ifx 2026.2.0 and Intel MPI 2021.19.0 (Ubuntu 24.04, gcc 13 for the C side); HDF5 2.3.0 built by ifx; zlib, LZ4, LZMA, FFTW 3; the tools. Also `-lite` (no Intel MPI development files, no HDF5), `-gui` |

**The tools**, in every image: FoBiS 3.16.9, ford 7.0.13, formal 0.2.16, numpy 2.5.3, h5py 3.16.0 (venv `/opt/venv`);
fpm 0.13.0, CMake 4.4.4, ninja 1.13.2, Node 24.13.0 + npm, ShellCheck 0.9.0, zsh 5.9, fish 4.9.3, PowerShell 7.7.0;
git, jq, GNU awk, make, pkg-config, curl.

The same stack as the workstations (Lmod `gcc/16.2.0`, `openmpi/5.0.11-gnu16.2.0`, ADAM's `lib/hdf5/develop/gnu/16.2.0`),
but HDF5 has the deflate filter. Each image is also tagged with its build date (`gnu-16.2-20261111`) to pin a build.

Compressed (pulled) sizes: `gnu-16.2` 0.9 GB, `oneapi-2026.2` 1.7 GB, `nvhpc-26.9` 3.9 GB (9 GB on disk; a hosted
`ubuntu-24.04` runner has 86 GB free on `/`). The NVIDIA SDK is trimmed of what compiling and CPU runs do not need: profilers,
examples, NCCL, NVSHMEM, CUDA forward compatibility, the static math libraries.

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

Nothing is installed when the job runs. The images set:

- `PATH`: the compilers, the tools (`/opt/tools/bin`, `/opt/cmake/bin`, the venv), the MPI wrappers (`mpifort`,
  `mpicc`, `mpirun`; Intel's `mpiifx` too) and the HDF5 tools; the SDK environment their own scripts would set
  (`NVHPC_ROOT`, the CUDA and math libraries; `CMPLR_ROOT`, `I_MPI_ROOT`), since no CI step sources them;
- `HDF5_ROOT=/opt/hdf5` (CMake's `find_package(HDF5)`); a FoBiS varset points at `/opt/hdf5/lib` and `/opt/hdf5/include`
  (static libraries: link `hdf5_fortran hdf5_f90cstub hdf5 z dl m`);
- with Open MPI (`gnu`, `nvhpc`'s HPC-X): `OMPI_ALLOW_RUN_AS_ROOT=1`, `OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1` (containers
  run as root) and oversubscription by default (`mpirun -np 4` on a 2-core runner); Intel MPI needs neither;
- git `safe.directory = *` (system config): `actions/checkout` marks the workspace safe only in a temporary `HOME`, so
  without it every later `git` of the job dies with "detected dubious ownership" (root on a checkout owned by the runner
  user).

A GUI program runs under Xvfb in `gnu-16.2-gui`: `xvfb-run -a -s "-screen 0 1280x1024x24" <program>` (24-bit; the
default screen is 640 x 480, 8-bit).

## The environment contract

Every toolchain, an image or a setup action, exports the same environment, so one project script runs on all of them
(`common/check-contract.sh` checks it at build time in every image and at the end of every setup action; the
*Contract* workflow checks the published images and the setups on their runners):

| Variable | Meaning |
|---|---|
| `FC`, `CC`, `CXX` | the Fortran compiler; the C/C++ companions (gcc/g++ beside gfortran, nvfortran and ifx; Apple clang on macOS) |
| `MPIFC`, `MPIRUN`, `HDF5_ROOT` | with MPI (the `full` flavour): the MPI Fortran wrapper, the launcher, HDF5 (`include/`, static `lib/`) |
| `TOOLCHAIN` | the toolchain id: `linux-gnu-16.2`, `linux-nvhpc-26.9`, `linux-oneapi-2026.2`, `macos-gnu`, `windows-gnu`, `linux-bare` |
| `TOOLCHAIN_OS`, `TOOLCHAIN_FAMILY` | `linux`, `macos`, `windows`; `gnu`, `nvf`, `intel` (also the suffix of the fobos modes: `tests-$TOOLCHAIN_FAMILY`) |

and `fobis`, `fpm`, `python3` (>= 3.11), `cmake`, `ninja`, `pkg-config` on `PATH`.

## Without an image: macOS, Windows, a fresh Linux runner

Containers run only on Linux runners, so the other platforms get a composite action of this repository:

```yaml
- uses: szaghi/fortran-toolchains/.github/actions/setup-macos@main     # macos-15; with: {flavour: full} adds Open MPI, HDF5
- uses: szaghi/fortran-toolchains/.github/actions/setup-windows@main   # windows-latest; steps then use shell: msys2 {0}
- uses: szaghi/fortran-toolchains/.github/actions/setup-linux-bare@main  # a fresh ubuntu-24.04 (installer tests)
```

- **macOS**: Homebrew gcc (the major of the `GCC` pin; `FC=gfortran-16`), fpm, ninja, pkg-config; CMake and FoBiS at
  their pins; `full`: Homebrew Open MPI and HDF5 at the pinned commit built from source, cached. `CC`/`CXX` are Apple
  clang.
- **Windows**: MSYS2 UCRT64 gfortran, fpm, CMake, ninja, pkgconf, Python, FoBiS at its pin. Lite only (no MPI).
- **Fresh Linux**: gcc/g++/gfortran from the `ubuntu-toolchain-r/test` PPA (its gcc 16 is a 16.0.1 snapshot), CMake,
  ninja, fpm, FoBiS at their pins.

Homebrew, MSYS2 and the PPA are rolling: they cannot install an exact version. A component within the major of its pin
is accepted with a warning annotation; another major fails the job (`check-versions.sh --policy major`).

## Reusable workflows

A project's CI is a few calls of this repository's workflows, pinned to the major tag `v1`:

```yaml
jobs:
  test:                       # tests with coverage in an image; the coverage-docs artifact for the docs
    uses: szaghi/fortran-toolchains/.github/workflows/test.yml@v1
  matrix:                     # a project script on any toolchains, any OS
    uses: szaghi/fortran-toolchains/.github/workflows/matrix.yml@v1
    with:
      toolchains: linux-gnu linux-nvhpc linux-oneapi macos-gnu windows-gnu
      script: scripts/ci/matrix.sh
  docs-examples:              # committed outputs must match their sources
    uses: szaghi/fortran-toolchains/.github/workflows/generated.yml@v1
    with:
      command: bash scripts/docs_examples.sh
      paths: docs/examples
  fpm:                        # fpm test and release build, with the toolchain's compilers
    uses: szaghi/fortran-toolchains/.github/workflows/fpm.yml@v1
```

| Workflow | What it does | Main inputs |
|---|---|---|
| `test.yml` | `FoBiS.py fetch` (when the project has dependencies), the coverage command (the scaffold's `makecoverage-analysis`), the coverage as output and summary, the coverage outputs under `docs/` packed for the docs (failing on an empty list) | `toolchain`, `command`, `pack-coverage` |
| `matrix.yml` | the project script on each toolchain: Linux ones in the images, macOS and Windows through the setup actions; a display for GUI programs (Linux: the `-gui` image under Xvfb; Windows: Mesa llvmpipe) | `toolchains`, `script`, `display`, `*-packages`, `artifacts` |
| `generated.yml` | the project's regeneration in an image, then any change or new file under the paths fails with the diff (docs examples, doctests) | `command`, `paths` |
| `fpm.yml` | `fpm test`, `fpm build --profile release`, with `FPM_FC`/`FPM_CC`/`FPM_CXX` from the toolchain | `toolchain`, `test-command`, `build-command` |

Every workflow takes `working-directory` (the project inside the repository) and `apt-packages`. A nightly run is a
caller's `schedule` on any of them.

**Toolchain ids carry no version** (`linux-gnu`, `linux-nvhpc`, `linux-oneapi`, `macos-gnu`, `windows-gnu`): the
workflows resolve them to the current images (`scripts/plan.sh`, from `versions.env`), so a version bump reaches every
project without touching its workflows.

**Versions**: the workflows use this repository's actions and scripts from a checkout at their input `toolchains-ref`,
default `v1`, the major tag the callers pin; `scripts/release.sh X.Y.Z` tags a release and moves `v1` once Build,
Contract and Selftest are green on it. The *Selftest* workflow calls every workflow on `tests/fixture` with
`toolchains-ref: ''` (this checkout), on all toolchains: the reusable workflows' gate.

## Locally

```bash
docker run --rm -it -v $PWD:/work -w /work ghcr.io/szaghi/fortran-toolchains:gnu-16.2 bash
```

A CI failure is reproduced with the same image, the same toolchain.

## Build

```bash
scripts/build.sh gnu full          # ghcr.io/szaghi/fortran-toolchains:gnu-16.2
scripts/build.sh gnu lite          # ...:gnu-16.2-lite
scripts/build.sh gnu gui           # ...:gnu-16.2-gui
scripts/build.sh nvhpc full        # ...:nvhpc-26.9      (oneapi: ...:oneapi-2026.2)
scripts/build.sh gnu full --tag    # print the tag; --build-args prints the build arguments
```

One Dockerfile per vendor (`gnu/`, `nvhpc/`, `oneapi/`), the flavours as its build targets, the versions as build
arguments from `versions.env`, the build context the repository root: the recipes every vendor shares (base packages,
tools, venv, HDF5, checks) are the scripts of `common/`. `gnu` builds on the official `gcc` image (Debian) and compiles
Open MPI; `nvhpc` and `oneapi` build on Ubuntu (the WSL box's) and install the vendor's SDK from its apt repository at
the exact WSL version. A cold `gnu` build takes about 5 minutes on 16 cores; `nvhpc` downloads 5 GB. The *Build* workflow builds and pushes
every (vendor, flavour) when a vendor directory, `common/`, `versions.env`, `scripts/build.sh` or the workflow changes on
`main`, or on demand.

Each flavour checks itself while building, so a broken image is never pushed: every tool at its `versions.env` pin
(`common/check-versions.sh`); in every `full`, `check.f90` built by the image's MPI Fortran wrapper (the `mpi_f08` and
`hdf5` modules, a parallel HDF5 file written by 2 ranks, the deflate filter) and the LZ4/LZMA link; in every `-gui`, an
X server under Xvfb with Mesa's llvmpipe (`common/check-image.sh`).

## Versions

`versions.env` holds every version, each the latest installed on the WSL development box. `scripts/wsl-versions.sh`
(run there) compares the two and exits 1 on any drift; `scripts/wsl-versions.sh --write` rewrites `versions.env` from
WSL. When CI needs a newer tool than WSL has, WSL is upgraded first; the images follow. A new vendor is a directory
with its Dockerfile, a version rule in `scripts/build.sh`, and an entry in the workflow's matrix and `paths` filter.
