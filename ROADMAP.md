# Roadmap

fortran-toolchains becomes the single home of the CI of the Fortran projects: the toolchains (images, setups) and
the reusable workflows that use them. The FoBiS scaffold shrinks to thin per-repo callers. Baseline: the audit of
2026-11-13 (21 repositories with workflows). The step-by-step plan and its status are tracked in
[#2](https://github.com/szaghi/fortran-toolchains/issues/2).

## Rules

1. **Every toolchain tracks the latest version installed on the WSL box**: compilers, SDKs, MPI, HDF5 and tools
   alike. Read versions from the WSL box (Lmod stacks under `/opt`, not the apt `/usr/bin/gfortran`), never from a
   consumer's workflow.
2. **WSL is upgraded when CI needs a newer tool** (or a tool WSL lacks): the image then follows WSL. Never the other way.
3. **Repositories on older versions are ported** to the current toolchains; no image is kept for an old version,
   and no compatibility floor (older gfortran, older HDF5) is tested.
4. **Workflows are reusable and project-agnostic** (`workflow_call` here); the scaffold renders only callers with
   per-project inputs.
5. Out of scope: medooza and the clusters (handled separately), AMD (ROCm/amdflang), GPU execution.

## Versions

`versions.env` holds every pin, each the latest installed on the WSL box; `scripts/wsl-versions.sh` checks it against
WSL (`--write` regenerates it) and `common/check-versions.sh` checks every image against it at build time. Where WSL
gets each component: gcc `/opt/gcc/bin/<ver>` (Lmod), Open MPI `/opt/openmpi/bin/<ver>/gnu/<gcc>`, nvfortran and its
CUDA `/opt/nvidia/hpc_sdk/Linux_x86_64/<ver>`, ifx and Intel MPI `/opt/intel/oneapi/{compiler,mpi}/latest`, HDF5
ADAM's `lib/hdf5/develop/gnu/<gcc>` (no ifx build yet), Node nvm, FoBiS/ford/formal/cmake/ninja pipx, fpm the
release binary, numpy/h5py ADAM's regression venv, the shells apt (fish from its release-4 PPA) and Microsoft's
repository (pwsh).

Phase 0 (2026-11-13) upgraded WSL where CI needed more: fpm 0.12.0 → 0.13.0 (0.12.0 rejects the `[features]` table
of fpm.toml), cmake 3.28.3 → 4.4.4 and ninja → 1.13.2 (pipx), zsh, fish and pwsh installed (FLAP's completion tests).

## Images (Linux, `container:`)

One Dockerfile per vendor, parametrised by version, with flavours as build targets; the build matrix produces the
tags. Each image: the compiler, its MPI, HDF5 2.3.0 built by that compiler, the shared tool layer.

| Tag | Contents | Status |
|---|---|---|
| `gnu-16.2` (+ `-lite`, `-gui`) | gfortran 16.2.0, Open MPI 5.0.11, HDF5 2.3.0, FFTW 3, LZ4, LZMA | done (Phase 1): `gnu/Dockerfile`, flavours `lite`/`full`/`gui` |
| `nvhpc-26.9` (+ `-lite`, `-gui`) | nvfortran 26.9, HPC-X (Open MPI 5.0), CUDA 13.3, HDF5 2.3.0 (ADAM's `nvf/26.9` recipe) | done (Phase 2): Ubuntu 24.04 + NVIDIA's apt package at the exact version, trimmed 15 → 7.6 GB (profilers, examples, NCCL, NVSHMEM, CUDA `compat`, static math libraries); 3.9 GB compressed. Compile and CPU runs on hosted runners. |
| `oneapi-2026.2` (+ `-lite`, `-gui`) | ifx 2026.2.0, Intel MPI 2021.19.0, HDF5 2.3.0 (built by `mpicc`/`mpiifx`) | done (Phase 2): Ubuntu 24.04 + Intel's apt packages at the exact versions (not the hpckit image); 1.7 GB compressed |
| `<vendor>-<ver>-gui` | + SDL/X11/Wayland headers, Xvfb, Mesa (llvmpipe) | done for the three vendors |

**Shared tool layer** (done in `gnu`, Phase 1), every tool at its `versions.env` pin: CMake, ninja, Node + npm
(drops `setup-node` and the EOL Node 20), fpm, ShellCheck, fish, PowerShell as upstream release binaries; zsh from
the distribution; FoBiS, ford, formal, numpy, h5py (ADAM's regression oracles) pinned in the venv; git, jq, GNU awk.
A pin change rebuilds its layer, so the build cache cannot keep a stale tool. gcovr is gone (unused).

## Setups (no container possible)

Done in Phase 3 (local gates; their runners are the Contract workflow's). On rolling platforms a component within the
major of its pin warns, another major fails (`check-versions.sh --policy major`).

| Setup | Contents | Who | Measured on 2026-11-13 |
|---|---|---|---|
| `setup-macos` | Homebrew gcc (`FC=gfortran-<major>`), fpm, ninja, pkg-config; CMake (release binary) and FoBiS at their pins; `full`: Homebrew Open MPI + HDF5 at the pinned commit from source, cached; `CC`/`CXX` = Apple clang | `matrix` (figure, StringiFor), figure installer/fpm consumers | Homebrew: gcc 16.2.0, open-mpi 5.0.11, fpm 0.13.0, ninja 1.13.2 exact; hdf5-mpi 2.2.0 (hence the source build); cmake 4.5.0 (hence the binary) |
| `setup-windows` | MSYS2 UCRT64 gcc-fortran, fpm, cmake, ninja, pkgconf, python + `python-pydantic`, FoBiS at its pin; lite only (no MS-MPI) | `matrix` (figure), fpm consumers | MSYS2: gcc-fortran 16.2.0, fpm 0.13.0, ninja 1.13.2 exact; cmake 4.4.5 (warns) |
| `setup-linux-bare` | gcc/g++/gfortran of the GCC major from the `ubuntu-toolchain-r/test` PPA, CMake, ninja, fpm, FoBiS at their pins | install.yml, figure installer (a fresh machine, not an image) | the PPA's only gcc 16 for noble is the `16-20260315` snapshot (16.0.1): warns |

## Reusable workflows (`workflow_call`)

Inputs carry the project specifics (toolchain, fobos modes, check paths, packages); nothing names a repository.

| Workflow | Replaces | Status |
|---|---|---|
| `test` (fetch, tests with coverage, coverage output, coverage-docs artifact) | scaffold ci.yml, ADAM `test` | done (Phase 4) |
| `matrix` (a project script on a list of toolchains, any OS; see below) | FLAP/forbear matrix.yml, StringiFor compilers.yml, figure platforms.yml | done (Phase 4) |
| `generated` (regenerate, then any change under the paths fails with the diff) | docs-examples of FiNeR, FoXy, FUNDAL, StringiFor, VecFor, VTKFortran, FLAP/forbear jobs; doctests-sync of BeFoR64, StringiFor | done (Phase 4): one workflow, both are "regenerate, then diff" |
| `fpm` (test, release build, the toolchain's compilers) | VecFor, VTKFortran, figure, FLAP/forbear jobs | done (Phase 4); publishing (figure's fpm tag) not yet |
| `docs` (build on `workflow_run`, deploy with a long `deploy-pages` timeout) | scaffold docs.yml, FOSSIL's timeout patch, ADAM docs.yml, appelbe docs.yml | done (Phase 4): coverage `auto`/`run`/`none` (appelbe: `none`), `build-command` (ADAM's has no `predocs:build`), 30-minute deploy timeout |
| `release`, `install` (bare runner, `setup-linux-bare`) | scaffold release.yml, install.yml | done (Phase 4): `release` with `dry-run`; `install` per build system the tarball carries |
| nightly runs | FOSSIL validation.yml | a caller's `schedule` on `matrix` or `test`: no workflow of its own |

`test` stays separate from `matrix` for now (its coverage feeds the docs artifact); merging them (`matrix` with one
toolchain and `coverage: true`) is reconsidered once both exist.

### `matrix`: toolchains × a project script

A toolchain is an (OS, compiler) pair: compilers and platforms are one axis. The workflow provisions toolchains and
platform capabilities; the project owns its pipeline as a script.

**Toolchain ids** carry no version: `scripts/plan.sh` resolves a Linux id to the current image (versions.env), so a
version bump reaches every caller unchanged (rule 3). `TOOLCHAIN` inside the image keeps the version.

| id | runner | provided by |
|---|---|---|
| `linux-gnu` | ubuntu-24.04 | container `gnu-16.2` (`-gui` with `display: true`) |
| `linux-nvhpc` | ubuntu-24.04 | container `nvhpc-26.9` (compile and CPU run only) |
| `linux-oneapi` | ubuntu-24.04 | container `oneapi-2026.2` |
| `macos-gnu` | macos-15 (arm64) | `setup-macos` (Homebrew gcc, the WSL major) |
| `windows-gnu` | windows-latest | `setup-windows` (MSYS2 UCRT64) |

**Environment contract**, exported by every toolchain, container or setup alike:
`FC CC CXX MPIFC MPIRUN HDF5_ROOT`; `TOOLCHAIN` (the id), `TOOLCHAIN_OS` (`linux|macos|windows`),
`TOOLCHAIN_FAMILY` (`gnu|nvf|intel`); fobis, fpm, python ≥ 3.11, cmake, ninja, pkg-config on `PATH`. `CC`/`CXX` are the
platform's natural companions (Apple clang on macOS; gcc/g++ beside nvfortran and ifx, which link libstdc++).

**Project script**: input `script` (default `scripts/ci/matrix.sh`), run with the contract environment. The same
script runs on WSL, in `docker run <image>`, and in CI; per-compiler differences are `case $TOOLCHAIN_FAMILY` in it
or fobos modes. fobos modes use the family suffix: `tests-gnu`, `tests-nvf`, `tests-intel`.

**Other inputs**: `display` (Linux: the `-gui` image with Xvfb, 24-bit, `DISPLAY` exported; Windows: Mesa llvmpipe
and a 1920×1080 display; macOS: nothing), `apt-packages`, `brew-packages`, `msys2-packages`, `artifacts` (uploaded
as `<name>-<toolchain>`).

**Mechanics**: a `plan` job splits `toolchains` into a Linux, a macOS and a Windows matrix, one job each (no
`container:` off Linux; the Windows job's default shell is `msys2 {0}`); a job with an empty matrix is skipped.

A caller (figure):

```yaml
jobs:
  matrix:
    uses: szaghi/fortran-toolchains/.github/workflows/matrix.yml@v1
    with:
      toolchains: linux-gnu linux-nvhpc linux-oneapi macos-gnu windows-gnu
      script: scripts/ci/matrix.sh
      display: true
      brew-packages: sdl3
      msys2-packages: sdl3 mesa
      artifacts: window-frames
```

### Versioning

A reusable workflow cannot use its own repository's actions by relative path (`./` resolves in the caller's
checkout), and `uses:` takes no expressions. Decided in Phase 4: each workflow checks out this repository at its input
`toolchains-ref` (default `v1`) into `.fortran-toolchains/` and uses the actions and scripts from there by local
path. Pinning `@v1` inside the workflows instead would make the self-test run the released actions, not the commit
under test; with the checkout, Selftest passes `toolchains-ref: ''` (this checkout). `v1` is a moving major tag that
callers pin (`uses: .../matrix.yml@v1`); `scripts/release.sh X.Y.Z` tags a release and moves `v1` once Build,
Contract and Selftest are green on it. Images are versioned by their own tags (`gnu-16.2`), resolved at run time.

## Ports

| Repository | Today | Port |
|---|---|---|
| FLAP, forbear | `matrix.yml` gfortran 13–16; forbear nvfortran 26.1, ifx 2025.3 | `matrix` on the three Linux toolchains; the GNU 13–15 legs go (rule 3) |
| StringiFor | ifx 2025.3 + macOS gcc 14; doctests-sync, utf8-harness on gcc 14 | `matrix` (`linux-oneapi-2026.2 macos-gnu`; the REAL(16) probe moves into its script); the rest in `gnu-16.2` |
| figure | nvfortran 26.9 and ifx 2026.1 installed per run; macOS gcc 14; modes `tests-ifx` | `matrix` on all five toolchains with `display: true`; modes renamed `tests-intel` |
| FoXy, VecFor, VTKFortran, FUNDAL | docs-examples on gcc 14 (FUNDAL: apt gfortran, `-fopenacc`) | `docs-examples` in `gnu-16.2`; the committed outputs regenerate once |
| VecFor | fpm.yml on gcc 14 | `fpm` |
| VTKFortran | hdf5.yml serial HDF5 1.10 (the "oldest supported") | the 1.10 job goes (rule 3); the hdf5-mpi job stays |
| BeFoR64 | doctests-sync on gcc 14 | `doctests-sync` |
| ADAM | gfortran 14 + HDF5 2.0.0 (`ci_gnu`), 1.5 GB of committed `lib/hdf5` per checkout, no nvfortran | `gnu-16.2` with a `$HDF5_PREFIX = /opt/hdf5` varset; a compile-only FNL/NVF job on `nvhpc-26.9` |
| appelbe | hand-made docs.yml (no Fortran, no CI) | `docs` with a no-CI trigger |
| every repo | Node 20 actions and `node-version: '20'` | Node 24 in the images; actions at their Node 24 majors |

Blockers met on the way, not toolchain issues: FiNeR and FLAP `CMakeLists.txt` declare stale `project(VERSION)`
(the scaffold's `release.sh` refuses to release them); VTKFortran's fpm job and FOSSIL's Pages timeout are lost by a
scaffold sync until `fpm` and `docs` absorb them; FOSSIL's nightly validation fails 2 of 35 programs (2026-11-12); PENF v2.0.1's `makefile` passes `-DR16P`, which the
sources renamed `PENF_R16P`, so its make install fails (found by `install`, 2026-11-13; Selftest skips that leg).

## Deferred

AMD (TheRock/amdflang, gfx103X on WSL); LLVM flang (source only on WSL, not built); GPU execution (needs a
self-hosted or paid GPU runner); linux/arm64 images; medooza and the clusters.
