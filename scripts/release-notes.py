#!/usr/bin/env python3
"""Print the release notes of a tag: its section of a changelog (git-cliff's "## [1.2.3] - date").

    release-notes.py TAG [CHANGELOG]      CHANGELOG defaults to CHANGELOG.md

The heading may carry the tag's "v" or not (cliff.toml writes it without). The section runs to the next "## "
heading. Without the file or the section, a pointer to the changelog. Used by the release workflow.
"""

import re
import sys
from pathlib import Path


def notes(tag: str, changelog: Path) -> str:
    """Return the section of `changelog` for `tag`, or a pointer to the changelog."""
    version = re.escape(tag.removeprefix("v"))
    if changelog.is_file():
        pattern = rf"^## \[v?{version}\][^\n]*\n.*?(?=^## |\Z)"
        match = re.search(pattern, changelog.read_text(encoding="utf-8"), re.DOTALL | re.MULTILINE)
        if match:
            return match.group(0).strip()
    return f"Release {tag}\n\nSee {changelog.name} for details."


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3) or argv[1].startswith("-"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    print(notes(argv[1], Path(argv[2] if len(argv) == 3 else "CHANGELOG.md")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
