#!/usr/bin/env bash
# Regenerate the outputs the documentation shows: build the examples, run each, write docs/examples/<name>.txt.
set -euo pipefail
fobis build --mode examples-gnu
./exe/examples/fixture_example_sum > docs/examples/sum.txt
