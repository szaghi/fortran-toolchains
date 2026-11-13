# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Container images of the Fortran toolchains that the projects under `~/fortran/` use in CI and to reproduce CI locally.
Each image is **one compiler plus the MPI and HDF5 built by that compiler**, so every `.mod` (`mpi_f08`, `hdf5`) is
readable by the image's compiler. One Dockerfile per vendor: `gnu/` (gfortran 16.2.0, Open MPI 5.0.11), `nvhpc/`
(nvfortran 26.9, HPC-X, CUDA 13.3), `oneapi/` (ifx 2026.2.0, Intel MPI 2021.19.0), each with HDF5 develop `ab5df552`
(2.3.0) built by its compiler; three flavours, published as `ghcr.io/szaghi/fortran-toolchains:<vendor>-<major.minor>`
(`full`), `…-lite`, `…-gui`, each also tagged `<tag>-YYYYMMDD`. Where it is going (more vendors, macOS/Windows setups,
reusable workflows, a thin FoBiS scaffold): `ROADMAP.md`, tracked in issue #2.

## Commands

```bash
# build an image (versions from versions.env; gnu ~5 min cold on 16 cores; nvhpc downloads 5 GB)
scripts/build.sh gnu full --build-arg JOBS=16      # :gnu-16.2      (lite, gui: :gnu-16.2-lite, :gnu-16.2-gui)
scripts/build.sh nvhpc full                        # :nvhpc-26.9    (oneapi full: :oneapi-2026.2)
REGISTRY=local scripts/build.sh gnu lite           # tag local:gnu-16.2-lite instead of ghcr.io/...
scripts/build.sh gnu full --tag                    # the tag; --build-args: the KEY=VALUE build arguments

# the versions rule: versions.env vs the WSL box (exit 1 on drift); --write rewrites versions.env from WSL
scripts/wsl-versions.sh

# rerun the checks in a built image (the same commands the Dockerfile runs)
docker run --rm ghcr.io/szaghi/fortran-toolchains:gnu-16.2 bash -c 'cd /tmp \
  && mpifort -I/opt/hdf5/include /opt/toolchain/check.f90 -o check \
     -L/opt/hdf5/lib -lhdf5_fortran -lhdf5_f90cstub -lhdf5 -lz -ldl -lm && mpirun -np 2 ./check'
docker run --rm -e FPM=0.13.0 ghcr.io/szaghi/fortran-toolchains:gnu-16.2 /opt/toolchain/check-versions.sh FPM

# the environment contract in an image; the drift-policy tests, under bash 5 and macOS's bash 3.2
docker run --rm -v "$PWD:/repo:ro" -w /repo ghcr.io/szaghi/fortran-toolchains:gnu-16.2 common/check-contract.sh --mpi
bash tests/check-versions.sh
docker run --rm -v "$PWD:/r" -w /r bash:3.2 bash tests/check-versions.sh

# reproduce a project's CI failure inside the image
docker run --rm -it -v $PWD:/work -w /work ghcr.io/szaghi/fortran-toolchains:gnu-16.2 bash

# CI status
gh run list -L 5
```

There is no other test suite: the build-time checks are the tests, and real consumers are the integration check (a
project's CI test step, `fobis fetch` + `FoBiS.py rule --ex makecoverage-analysis`, run in the image on a scratch clone,
never in the project's own tree: the container writes as root).

## Architecture

- **Shared recipes in `common/`, vendor specifics in the Dockerfiles.** `install-tools.sh` (CMake; ninja, Node, fpm,
  ShellCheck, fish, PowerShell: upstream release binaries, checksums where published), `install-base.sh` (distribution
  packages per flavour, Debian or Ubuntu; the system `safe.directory`), `install-venv.sh` (pinned FoBiS, ford, formal,
  numpy, h5py), `build-hdf5.sh <mpicc> <mpifort>` (HDF5 parallel, Fortran, HL, **static only**, `-fPIC`, deflate on,
  szip off), `check-versions.sh`, `check-image.sh`, `check.f90`. A Dockerfile has download stages (`cmake` alone, so
  a tool bump never rebuilds HDF5; `tools`), a compiler stage, a `build` stage (HDF5, and in `gnu` Open MPI first),
  and the public flavours: `lite` (compiler + tools + venv), `full` (+ MPI development, HDF5, FFTW, LZ4, LZMA), `gui`
  (+ X11/Wayland headers, Xvfb, Mesa).
- **Bases.** `gnu` builds on the official `gcc:<ver>` (Debian) and compiles Open MPI. `nvhpc` and `oneapi` build on
  `ubuntu:$UBUNTU` (the WSL box's distribution) and install the SDK from the vendor's apt repository at the exact WSL
  version (`apt-cache madison` resolves `<ver>-<build>`: a bare package name would take a newer patch release). The
  SDK environment their `vars.sh`/modulefile would set is written as `ENV` (no CI step sources anything). `nvhpc`'s SDK
  is trimmed in its install layer (15 → 7.6 GB: profilers, examples, NCCL, NVSHMEM, CUDA `compat`, `*_static.a` math
  libraries); its apt package also pulls Ubuntu's gfortran 13 (a dependency), which the image does not use.
- **Versions are build arguments, from `versions.env` only.** `scripts/build.sh` passes them (locally and in CI); no
  ARG has a default, so a build without them fails instead of using a stale version. The build context is the repository
  root (`.dockerignore` sends only `common/`: the Dockerfiles copy nothing else; `-f <vendor>/Dockerfile`).
- **The checks are `RUN`s in the Dockerfile**, not CI steps: `common/check-versions.sh` (every component at its pin) in
  every flavour; `common/check-image.sh`: `check.f90` built by the image's MPI Fortran wrapper (`mpifort`, `mpiifx`)
  and run on 2 ranks (a collective parallel-HDF5 write, the deflate filter) and the LZ4/LZMA link in `full`; Xvfb + `glxinfo` showing llvmpipe in `gui`; `git` on a repo owned by uid 1001. A failing check fails the
  build, so `build-push-action` never pushes a broken image.
- **The environment contract** (`common/check-contract.sh`; table in README): `FC CC CXX TOOLCHAIN TOOLCHAIN_OS
  TOOLCHAIN_FAMILY`, with MPI `MPIFC MPIRUN HDF5_ROOT`, and fobis, fpm, python3 >= 3.11, cmake, ninja, pkg-config on
  `PATH`. The images set it as `ENV` (`TOOLCHAIN` comes from `scripts/build.sh`, which owns the tag and id format) and
  check it at build time; the setup actions export it through `$GITHUB_ENV`/`$GITHUB_PATH` and check it last.
- **Setup actions** (`.github/actions/setup-{macos,windows,linux-bare}`, for runners that cannot run a container):
  thin composite actions over `setup/macos.sh` (phases `tools` and `hdf5`, the HDF5 cache restored between
  them, keyed on the gfortran and Open MPI versions actually installed) and `setup/linux-bare.sh`; Windows is
  inline MSYS2. They read `versions.env` from `$GITHUB_ACTION_PATH/../../..` and check versions with
  `check-versions.sh --policy major`: Homebrew, MSYS2 and the PPA are rolling, so a same-major drift warns, another
  major fails. The images use the default `exact` policy.
- **Contract workflow** (`.github/workflows/contract.yml`): the published `full` images as job containers (their tags
  computed by `scripts/build.sh` from `versions.env`, never written in the workflow) and the three setups on their
  runners. Runs after a successful Build, and on changes to the actions or `common/`.
- **CI (`.github/workflows/build.yml`)** builds and pushes one job per (vendor, flavour) on push to `main` (filtered by
  `paths`) or by `workflow_dispatch`. The layer cache is in the registry (`cache-<vendor>-<flavour>` tags): the GHA
  cache's 10 GB per repository cannot hold the NVIDIA SDK layer beside the others. A hosted `ubuntu-24.04` runner has
  145 GB on `/`, 86 GB free (measured 2026-11-13): no job needs to free disk, not even `nvhpc`'s (5 GB download, 15 GB
  installed before the trim). `REGISTRY` comes from `github.repository`.

## The consumer contract

The projects do not reference this repo directly. FoBiS scaffold renders their `ci.yml` (test job) and `docs.yml`
(build job) with `container: <image>` from the `toolchain_image` key in each project's `fobos` `[scaffold]` section
(see `~/python/FoBiS/docs/cookbook/ecosystem.md`, and `fobis/Fobos.py`). With that key set, the jobs install
nothing: the image **is** the environment. Anything the scaffold's workflows and scripts call must therefore be in the
image. Both post-release fixes in the git log came from this:

- **GNU awk**: `compute-coverage.sh` uses `match()` with an array argument; Debian ships only mawk.
- **`git config --system --add safe.directory '*'`**: `actions/checkout` marks the workspace safe only in a temporary
  `HOME`; without it every later `git` dies with "dubious ownership". The coverage pack step then failed silently, and
  `docs.yml` published a stale `coverage.json`.

Before you remove a package or tool from the image, grep the FoBiS scaffold templates and the consumers'
workflows (`grep -rl fortran-toolchains ~/fortran/*/.github/workflows`; about 18 repos) for its use. A project
installs what it alone needs through `toolchain_packages`, not through this image.

Environment that consumers rely on: `PATH` (venv, `/opt/tools/bin`, `/opt/cmake/bin`, `/opt/hdf5/bin`,
`/opt/openmpi/bin`), `HDF5_ROOT=/opt/hdf5` (CMake `find_package(HDF5)`), the static link line
`hdf5_fortran hdf5_f90cstub hdf5 z dl m`, `OMPI_ALLOW_RUN_AS_ROOT{,_CONFIRM}=1` (containers run as root), and
`PRTE_MCA_rmaps_default_mapping_policy=:oversubscribe` (`mpirun -np 4` on a 2-core runner).

## Adding or changing a toolchain

- **Every component tracks the latest version installed on the WSL box** (newest `/opt/gcc/bin/<ver>`,
  `/opt/nvidia/hpc_sdk/Linux_x86_64/<ver>`, `/opt/intel/oneapi/compiler/latest`, the pipx/apt tools, …; Lmod-managed
  stacks, not the apt `/usr/bin/gfortran`). Read versions from the WSL box (`scripts/wsl-versions.sh --write`), never
  from a consumer's workflow. When CI needs a newer tool than WSL has, WSL is upgraded first. No image is kept for an
  old version: repos still on older ones get ported. MPI and HDF5 match the workstation build (ADAM's HDF5 commit);
  the only intended difference is HDF5's deflate filter.
- A new pin: a line in `versions.env`, a probe in `scripts/wsl-versions.sh` and in `common/check-versions.sh`, an `ARG`
  in the stage that uses it, its name in that flavour's `check-versions.sh` call.
- A new vendor: a directory with its `Dockerfile` (reusing `common/`), a version rule in `scripts/build.sh`
  (`case $vendor`: the version its tag carries), and an entry in the `matrix.vendor` **and** the `paths` filter of
  `build.yml` (without it a push to the directory does not trigger a build).
- Any change to `build.yml`, `versions.env`, `common/` or `scripts/build.sh` rebuilds every image in the matrix.
- Projects move to a new toolchain by changing `toolchain_image` in each `fobos`, then `fobis scaffold sync`.

## Gotchas

- **Scripts a setup action runs must work in bash 3.2 and MSYS2** (macOS's `/bin/bash`; Windows): no associative
  arrays, `${var,,}`, `find -printf`, `readarray`; `shasum -a 256` on macOS (no `sha256sum`); `cygpath -u` turns the
  Windows `$GITHUB_ACTION_PATH` into a path MSYS2's bash reads. Test with `docker run bash:3.2`.
- The macOS and Windows setups cannot be run locally: `setup/macos.sh` can be driven on Linux with a stub `brew`
  and `gfortran-16` pointing at a real gfortran (WSL's gcc 16.2 and Open MPI 5.0.11 stand in for Homebrew's), and
  `setup/linux-bare.sh` runs as-is in a plain `ubuntu:24.04` container.
- Editing `common/install-tools.sh` invalidates the `cmake` stage, hence every HDF5 build (a few minutes per vendor).

- **Never edit a script while a background job runs it**: bash reads scripts incrementally, and the running process
  resumes at its old byte offset in the new file (a `syntax error near unexpected token` that is not in the file).
- **Tags are mutable.** All consumers track the floating `:gnu-16.2`, so a push reaches every project's next CI run.
  A second build on the same day overwrites the date tag.
- **Upstream checksum files are not uniform**: PowerShell's `hashes.sha256` is UTF-16LE with CRLF (`iconv` first);
  ninja, ShellCheck and fish publish none.
- h5py's wheel bundles its own serial HDF5 (2.0.0 with h5py 3.16.0), distinct from `/opt/hdf5`; the file format is
  compatible, the library is not the image's.
