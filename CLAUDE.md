# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Container images of the Fortran toolchains that the projects under `~/fortran/` use in CI and to reproduce CI locally.
Each image is **one compiler plus the MPI and HDF5 built by that compiler**, so every `.mod` (`mpi_f08`, `hdf5`) is
readable by the image's compiler. One directory per toolchain (`gnu-16.2/` today: gfortran 16.2.0, Open MPI 5.0.11,
HDF5 develop `ab5df552` = 2.3.0), published as `ghcr.io/szaghi/fortran-toolchains:<toolchain>` plus a
`<toolchain>-YYYYMMDD` tag.

## Commands

```bash
# build (≈30 min cold: Open MPI and HDF5 from source; JOBS defaults to 8, CI passes 4)
docker build -t ghcr.io/szaghi/fortran-toolchains:gnu-16.2 gnu-16.2
docker build --build-arg JOBS=16 -t ghcr.io/szaghi/fortran-toolchains:gnu-16.2 gnu-16.2

# rerun the toolchain check in a built image (the same commands the Dockerfile runs)
docker run --rm ghcr.io/szaghi/fortran-toolchains:gnu-16.2 bash -c 'cd /tmp \
  && mpifort -I/opt/hdf5/include /opt/toolchain/check.f90 -o check \
     -L/opt/hdf5/lib -lhdf5_fortran -lhdf5_f90cstub -lhdf5 -lz -ldl -lm && mpirun -np 2 ./check'

# reproduce a project's CI failure inside the image
docker run --rm -it -v $PWD:/work -w /work ghcr.io/szaghi/fortran-toolchains:gnu-16.2 bash

# CI status
gh run list -L 5
```

There is no other test suite: `check.f90` is the test, and a real consumer (e.g. VTKFortran's suites, a FoBiS
`fobis fetch && fobis build --mode tests-gnu-debug` inside the container) is the integration check.

## Architecture

- **Two-stage Dockerfile.** The `build` stage (`FROM gcc:<ver>`) compiles Open MPI (Fortran bindings, internal
  PMIx/hwloc/libevent) into `/opt/openmpi`, then HDF5 with CMake using `mpicc`/`mpif90` into `/opt/hdf5` (parallel,
  Fortran, HL, **static only**, `-fPIC`, deflate on, szip off). The runtime stage (same `gcc` base) copies `/opt/openmpi`
  and `/opt/hdf5`, installs the Debian tools, and puts the Python tools in the venv `/opt/venv`, because Debian's
  Python is externally managed.
- **The check gate is a `RUN` in the Dockerfile**, not a CI step: it compiles `check.f90` against the image's
  modules, runs it on 2 ranks (a collective parallel-HDF5 write, the deflate filter registered), and runs `git` on a
  repo owned by uid 1001. If any of these fails, the image is never built, so `build-push-action` never pushes it.
- **CI (`.github/workflows/build.yml`)** builds and pushes on push to `main` (filtered by `paths`) or by
  `workflow_dispatch`, one matrix entry per toolchain, with the GHA layer cache scoped per toolchain.

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

Environment that consumers rely on: `PATH` (venv, `/opt/hdf5/bin`, `/opt/openmpi/bin`), `HDF5_ROOT=/opt/hdf5` (CMake
`find_package(HDF5)`), the static link line `hdf5_fortran hdf5_f90cstub hdf5 z dl m`, `OMPI_ALLOW_RUN_AS_ROOT{,_CONFIRM}=1`
(containers run as root), and `PRTE_MCA_rmaps_default_mapping_policy=:oversubscribe` (`mpirun -np 4` on a 2-core
runner).

## Adding or changing a toolchain

- A new toolchain is a new directory (`gnu-17.1/`, `nvhpc-26.9/`) with its own `Dockerfile` and `check.f90`, **plus**
  a `matrix.toolchain` entry **and** a `paths` entry in `build.yml`. Without the `paths` entry, a push to the new
  directory does not trigger a build.
- Any change to `build.yml` rebuilds every toolchain in the matrix.
- Keep the stack identical to the workstations' (`~/.claude/CLAUDE.md` § Toolchains; ADAM's HDF5 commit). The only
  intended difference is HDF5's deflate filter.
- Projects move to a new toolchain by changing `toolchain_image` in each `fobos`, then `fobis scaffold sync`.

## Gotchas

- **The pip layer is unpinned and cached.** `FoBiS.py ford formal-ford2vitepress gcovr …` have no versions, and
  `cache-from: type=gha` reuses that layer until an earlier layer changes. A rebuild does not pick up a new FoBiS
  release unless you invalidate the layer (pin versions, or change something earlier in the Dockerfile).
- **Tags are mutable.** All consumers track the floating `:gnu-16.2`, so a push reaches every project's next CI run.
  A second build on the same day overwrites the date tag.
- The image reports versions at the end of the check `RUN` (`gfortran`, `mpifort`, `mpirun`, `fobis`). Read them in
  the build log after a change.
