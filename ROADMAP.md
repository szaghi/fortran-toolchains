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

## WSL snapshot (2026-11-13)

| Component | Version on WSL | Where |
|---|---|---|
| gcc / gfortran | 16.2.0 | `/opt/gcc/bin/16.2.0` (Lmod `gcc/16.2.0`) |
| Open MPI (GNU) | 5.0.11 | `/opt/openmpi/bin/5.0.11/gnu/16.2.0` |
| nvfortran | 26.9, HPC-X; CUDA 13.3 (the only one bundled) | `/opt/nvidia/hpc_sdk/Linux_x86_64/26.9` |
| ifx / Intel MPI | 2026.2.0 / 2021.19 | `/opt/intel/oneapi/{compiler,mpi}/latest` |
| HDF5 | develop `ab5df552` (2.3.0) | ADAM `lib/hdf5/develop/{gnu/16.2.0,nvf/26.9}`; no ifx build yet |
| Node | 24.13.0 | nvm |
| FoBiS / ford / formal | 3.16.9 / 7.0.13 / 0.2.16 | pipx |
| fpm | 0.12.0 | `~/.local/bin` |
| cmake / ninja | 3.28.3 / 1.11.1 | apt |
| shellcheck | present | apt |

## WSL upgrades CI needs first (rule 2)

| Tool | WSL now | CI needs | Who |
|---|---|---|---|
| fpm | 0.12.0 | ≥ 0.13.0 (0.12.0 rejects the `[features]` table of fpm.toml) | VTKFortran, VecFor, FLAP, forbear, figure, every install leg |
| cmake | 3.28.3 | ≥ the image's (3.31.6, Debian trixie), else pin the image to WSL's | FLAP alt-build, BeFoR64 doctests-sync, VTKFortran hdf5, figure |
| zsh, fish, pwsh | absent | FLAP's shell-completion tests (pwsh's leg is silently skipped without it) | FLAP |
| gcovr | absent | none (the templates never call `fobis coverage`) | drop it from the image instead |

## Images (Linux, `container:`)

One Dockerfile per vendor, parametrised by version, with flavours as build targets; the build matrix produces the
tags. Each image: the compiler, its MPI, HDF5 2.3.0 built by that compiler, the shared tool layer.

| Tag | Contents | Status |
|---|---|---|
| `gnu-16.2` | gfortran 16.2.0, Open MPI 5.0.11, HDF5 2.3.0, FFTW 3 | exists (single-directory layout, to refactor) |
| `nvhpc-26.9` | nvfortran 26.9, HPC-X, CUDA 13.3, HDF5 2.3.0 (recipe: ADAM's `nvf/26.9` build) | new; the SDK is 15 GB installed against ~14 GB free on a hosted runner: trim it (one CUDA, no NCCL/NVSHMEM) and free disk in the jobs. Compile-only on hosted runners. |
| `oneapi-2026.2` | ifx 2026.2.0, Intel MPI 2021.19, HDF5 2.3.0 (new recipe) | new; ifx and MPI from Intel's apt repository, not the hpckit image |
| `<vendor>-<ver>-gui` | + SDL/X11/Wayland headers, Xvfb, Mesa (llvmpipe) | new flavour: figure's display tests run on GNU, nvfortran and ifx |

**Shared tool layer**, pinned to the WSL versions: FoBiS, ford, formal (a lock file, so the build cache cannot
freeze a stale version); Node 24.13.0 + npm (drops `setup-node` and the EOL Node 20); fpm; ninja; shellcheck;
zsh, fish, pwsh; numpy, h5py (ADAM's regression oracles); cmake, git, jq, GNU awk.

## Setups (no container possible)

| Setup | Contents | Who | Caveat |
|---|---|---|---|
| `setup-macos` | Homebrew gcc 16 (the WSL major), open-mpi, ninja, pkg-config, fpm, python ≥ 3.11, FoBiS; exports the environment contract (`CC`/`CXX` = Apple clang) | `matrix` (figure, StringiFor), figure installer/fpm consumers | Homebrew is rolling: the major is matched, versions are logged, not pinned; `gcc@16` availability to verify |
| `setup-windows` | MSYS2 UCRT64 gcc-fortran, fpm, cmake, ninja, python + `python-pydantic` (FoBiS's typer; no pydantic-core wheel for MSYS2), FoBiS; exports the environment contract | `matrix` (figure), fpm consumers | MSYS2 is rolling: no pins |
| `setup-linux-bare` | gcc 16 from the toolchain PPA on a fresh runner | install.yml, figure installer (they must test a fresh machine, not the image) | the PPA builds of gcc 16 for 24.04 to verify (WSL's apt gfortran is a 16.0.1 trunk snapshot) |

## Reusable workflows (`workflow_call`)

Inputs carry the project specifics (toolchain, fobos modes, check paths, packages); nothing names a repository.

| Workflow | Replaces |
|---|---|
| `test` (build, tests, coverage, coverage artifact for the docs) | scaffold ci.yml, ADAM `test` |
| `docs` (build on `workflow_run`, deploy with a long `deploy-pages` timeout) | scaffold docs.yml, FOSSIL's timeout patch, ADAM docs.yml, appelbe docs.yml |
| `docs-examples` (regenerate, `git diff --exit-code`) | FiNeR, FoXy, FUNDAL, StringiFor, VecFor, VTKFortran, FLAP/forbear jobs |
| `doctests-sync` | BeFoR64, StringiFor |
| `fpm` (test, release build, publish) | VecFor, VTKFortran, figure, FLAP/forbear jobs |
| `matrix` (a project script on a list of toolchains, any OS; see below) | FLAP/forbear matrix.yml, StringiFor compilers.yml, figure platforms.yml |
| `nightly` (long validation runs) | FOSSIL validation.yml |
| `release`, `install` (bare runner) | scaffold release.yml, install.yml |

`test` stays separate from `matrix` for now (its coverage feeds the docs artifact); merging them (`matrix` with one
toolchain and `coverage: true`) is reconsidered once both exist.

### `matrix`: toolchains × a project script

A toolchain is an (OS, compiler) pair: compilers and platforms are one axis. The workflow provisions toolchains and
platform capabilities; the project owns its pipeline as a script.

**Toolchain ids** (versions per rule 1):

| id | runner | provided by |
|---|---|---|
| `linux-gnu-16.2` | ubuntu-latest | container `gnu-16.2` (`-gui` with `display: true`) |
| `linux-nvhpc-26.9` | ubuntu-latest | container `nvhpc-26.9` (compile and CPU run only) |
| `linux-oneapi-2026.2` | ubuntu-latest | container `oneapi-2026.2` |
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
      toolchains: linux-gnu-16.2 linux-nvhpc-26.9 linux-oneapi-2026.2 macos-gnu windows-gnu
      script: scripts/ci/matrix.sh
      display: true
      brew-packages: sdl3
      msys2-packages: sdl3 mesa
      artifacts: window-frames
```

### Versioning

A reusable workflow cannot use its own repository's actions by relative path (`./` resolves in the caller's
checkout), and `uses:` takes no expressions: the workflows reference
`szaghi/fortran-toolchains/.github/actions/<name>@v1`. Workflows, actions and the image tags they name are released
together under one moving major tag (`v1`); callers pin `@v1`.

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
scaffold sync until `fpm` and `docs` absorb them; FOSSIL's nightly validation fails 2 of 35 programs (2026-11-12).

## Deferred

AMD (TheRock/amdflang, gfx103X on WSL); LLVM flang (source only on WSL, not built); GPU execution (needs a
self-hosted or paid GPU runner); linux/arm64 images; medooza and the clusters.
