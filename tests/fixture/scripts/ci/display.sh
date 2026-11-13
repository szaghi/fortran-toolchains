#!/usr/bin/env bash
# The matrix workflow's display input (Linux): the script runs under an X server whose OpenGL is Mesa's llvmpipe.
set -euo pipefail
echo "DISPLAY=${DISPLAY:?no display}"
glxinfo -B | grep -E 'OpenGL renderer'
glxinfo -B | grep -q llvmpipe
