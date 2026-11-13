#!/usr/bin/env bash
# Tests of scripts/release-notes.py: the tag's section only (with or without the heading's "v", the last section to the
# end of the file), the pointer without the section or the file, the usage.
set -uo pipefail
notes=$(cd "$(dirname "$0")/.." && pwd)/scripts/release-notes.py
d=$(mktemp -d); trap 'rm -r "$d"' EXIT
cat > "$d/CHANGELOG.md" <<'MD'
# Changelog

## [1.2.3] - 2026-11-13

### Features

- three

## [v1.2.2] - 2026-11-12

- two

## [1.2.1] - 2026-11-11

- one
MD
pass=0 failed=0
expect() {   # expect <description> <exit status> <expected output> <command...>
  local what=$1 want=$2 out=$3 got rc; shift 3
  got=$("$@" 2> /dev/null); rc=$?
  if [ "$rc" = "$want" ] && [ "$got" = "$out" ]; then pass=$((pass + 1))
  else failed=$((failed + 1)); printf 'FAILED: %s (exit %s, wanted %s)\n--- got\n%s\n--- wanted\n%s\n' "$what" "$rc" "$want" "$got" "$out"; fi
}
expect 'first section'      0 $'## [1.2.3] - 2026-11-13\n\n### Features\n\n- three' python3 "$notes" v1.2.3 "$d/CHANGELOG.md"
expect 'tag without v'      0 $'## [1.2.3] - 2026-11-13\n\n### Features\n\n- three' python3 "$notes" 1.2.3 "$d/CHANGELOG.md"
expect 'heading with v'     0 $'## [v1.2.2] - 2026-11-12\n\n- two'                  python3 "$notes" v1.2.2 "$d/CHANGELOG.md"
expect 'last section'       0 $'## [1.2.1] - 2026-11-11\n\n- one'                   python3 "$notes" v1.2.1 "$d/CHANGELOG.md"
expect 'no prefix match'    0 $'Release v1.2\n\nSee CHANGELOG.md for details.'      python3 "$notes" v1.2 "$d/CHANGELOG.md"
expect 'dot is literal'     0 $'Release v1x2x3\n\nSee CHANGELOG.md for details.'    python3 "$notes" v1x2x3 "$d/CHANGELOG.md"
expect 'no file'            0 $'Release v1.2.3\n\nSee NEWS.md for details.'         python3 "$notes" v1.2.3 "$d/NEWS.md"
expect 'default changelog'  0 $'## [1.2.1] - 2026-11-11\n\n- one'                   bash -c "cd '$d' && python3 '$notes' v1.2.1"
expect 'usage'              2 ''                                                    python3 "$notes"
expect 'option'             2 ''                                                    python3 "$notes" --help
echo "release-notes.py: $pass passed, $failed failed"
[ "$failed" = 0 ]
