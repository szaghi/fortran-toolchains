# fixture

The project the reusable workflows of fortran-toolchains are tested on (`.github/workflows/selftest.yml`): a tiny
FoBiS library laid out as the projects are, with what each workflow drives.

| Workflow | What it runs here |
|---|---|
| `matrix` | `scripts/ci/matrix.sh`: `fobis build --mode tests-$TOOLCHAIN_FAMILY`, then `scripts/run_tests.sh`; `scripts/ci/display.sh` with `display: true` |
| `test` | `FoBiS.py rule --ex makecoverage-analysis` (the scaffold's coverage step): `docs/public/coverage.json` |
| `generated` | `scripts/docs_examples.sh`: regenerates `docs/examples/sum.txt`, the committed output of an example |
| `fpm` | `fpm test`, `fpm build --profile release` (`fpm.toml`, `test/`) |
