#!/usr/bin/env bash
# Release the reusable workflows, actions and scripts: tag vX.Y.Z and move the major tag vX to it, the tag the
# projects' callers pin (uses: .../matrix.yml@v1) and the workflows' default toolchains-ref. Run by the owner.
#
#   scripts/release.sh X.Y.Z            check, tag locally, print the push commands
#   scripts/release.sh X.Y.Z --push     check, tag, push both tags
#   scripts/release.sh X.Y.Z --no-ci    skip the CI check (tests of this script only)
#
# Refuses unless HEAD is main, up to date with origin/main, the tree clean, the version new, and the latest Build,
# Contract and Selftest runs on HEAD succeeded: a moved major tag reaches every project's next run.
set -euo pipefail

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
version=${1:-}; shift || true
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
push=0 ci=1
for a in "$@"; do
  case $a in --push) push=1 ;; --no-ci) ci=0 ;; *) usage ;; esac
done
tag=v$version major=v${version%%.*}
die() { echo "release.sh: $*" >&2; exit 1; }

[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "HEAD is not main"
[ -z "$(git status --porcelain)" ] || die "the working tree is not clean"
if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then die "$tag exists"; fi
sha=$(git rev-parse HEAD)
if [ "$ci" = 1 ]; then
  git fetch -q origin main
  [ "$sha" = "$(git rev-parse origin/main)" ] || die "HEAD is not origin/main: push first"
  for wf in build.yml contract.yml selftest.yml; do
    c=$(gh run list --workflow "$wf" --commit "$sha" -L 1 --json conclusion --jq '.[0].conclusion // "none"')
    [ "$c" = success ] || die "the latest $wf run on $sha is '$c', not success"
    echo "ok    $wf on ${sha:0:7}: success"
  done
fi

git tag -a "$tag" -m "fortran-toolchains $tag"
git tag -f -a "$major" -m "fortran-toolchains $major (at $tag)" > /dev/null
echo "tagged $tag and moved $major to ${sha:0:7}"
if [ "$push" = 1 ]; then
  git push origin "$tag"
  git push -f origin "$major"
else
  echo "push with: git push origin $tag && git push -f origin $major"
fi
