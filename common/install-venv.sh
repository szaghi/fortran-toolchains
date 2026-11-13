#!/usr/bin/env bash
# The Python tools of the CI in the venv /opt/venv (the distribution's Python is externally managed), pinned to the
# versions.env versions (build arguments, in the environment): FoBiS, ford, formal; numpy and h5py for the regression
# oracles (ADAM). The Markdown extensions are those the projects' ford.md files name (unpinned).
set -euo pipefail

python3 -m venv /opt/venv
/opt/venv/bin/pip install --no-cache-dir \
  "FoBiS.py==${FOBIS:?}" "ford==${FORD:?}" "formal-ford2vitepress==${FORMAL:?}" "numpy==${NUMPY:?}" "h5py==${H5PY:?}" \
  markdown markdown-include python-markdown-math toposort jinja2 pygments beautifulsoup4 tqdm importlib-metadata
