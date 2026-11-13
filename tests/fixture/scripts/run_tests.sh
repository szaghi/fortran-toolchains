#!/usr/bin/env bash
# Run every test program FoBiS built (exe/*test*); exit 1 if any fails.
set -uo pipefail
failed=0 n=0
for t in exe/*test*; do
  [ -x "$t" ] || continue
  n=$((n + 1))
  if "$t" > "$t.log" 2>&1; then echo "  PASS  ${t#exe/}"; else echo "  FAIL  ${t#exe/}"; cat "$t.log"; failed=$((failed + 1)); fi
done
[ "$n" -gt 0 ] || { echo "no test program in exe/"; exit 1; }
echo "$((n - failed))/$n passed"
[ "$failed" = 0 ]
