#!/usr/bin/env bash
# The Python tools of the CI in a venv (the distribution's Python is externally managed), pinned to the versions.env
# versions (build arguments in the environment, or a versions.env file):
#
#   install-venv.sh                          /opt/venv: FoBiS, ford, formal; numpy and h5py for the regression oracles
#                                            (ADAM); the Markdown extensions the projects' ford.md files name (unpinned)
#   install-venv.sh --fobis PREFIX PINS      PREFIX: FoBiS only, its pin read from the versions.env file PINS (the
#                                            setup actions of the runners without an image)
set -euo pipefail

if [ "${1:-}" = --fobis ]; then
  prefix=${2:?usage: install-venv.sh --fobis PREFIX PINS} pins=${3:?usage: install-venv.sh --fobis PREFIX PINS}
  fobis=$(sed -n 's/^FOBIS=//p' "$pins")
  python3 -m venv "$prefix"
  "$prefix/bin/python3" -m pip install --no-cache-dir --quiet "FoBiS.py==${fobis:?no FOBIS pin in $pins}"
  exit 0
fi

python3 -m venv /opt/venv
/opt/venv/bin/pip install --no-cache-dir \
  "FoBiS.py==${FOBIS:?}" "ford==${FORD:?}" "formal-ford2vitepress==${FORMAL:?}" "numpy==${NUMPY:?}" "h5py==${H5PY:?}" \
  markdown markdown-include python-markdown-math toposort jinja2 pygments beautifulsoup4 tqdm importlib-metadata
