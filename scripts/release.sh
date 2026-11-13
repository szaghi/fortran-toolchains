#!/usr/bin/env bash
# Release the reusable workflows, actions and scripts: tag vX.Y.Z and move the major tag vX to it, the tag the
# projects' callers pin (uses: .../matrix.yml@v1) and the workflows' default toolchains-ref. Run by the owner.
#
#   scripts/release.sh X.Y.Z            check, tag locally, print the push commands
#   scripts/release.sh X.Y.Z --push     check, tag, push both tags
#   scripts/release.sh X.Y.Z --no-ci    skip the CI check (tests of this script only)
#
# Refuses unless HEAD is main, up to date with origin/main, the tree clean, the version new, and Build, Contract and
# Selftest green for HEAD (each one's newest run since its paths last changed): a moved major tag reaches every
# project's next run.
set -euo pipefail

usage() { sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
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
  # each workflow runs on a push only when its paths change, and on the push's head commit only: the evidence is its
  # newest run on a commit from the newest one touching its paths up to HEAD (a push of docs alone runs no Build, and
  # the images it built before still stand)
  for wf in build.yml contract.yml selftest.yml; do
    mapfile -t paths < <(python3 -c 'import sys, yaml
on = yaml.safe_load(open(sys.argv[1]))[True]
print("\n".join(":(glob)" + p for p in on["push"]["paths"]))' ".github/workflows/$wf")
    [ "${#paths[@]}" -gt 0 ] || die "$wf has no push paths"
    at=$(git log -1 --format=%H "$sha" -- "${paths[@]}")
    [ -n "$at" ] || die "no commit touches the paths of $wf"
    commits=$(printf '%s\n' "$at"; git rev-list --ancestry-path "$at..$sha")
    run=$(gh run list --workflow "$wf" --branch main -L 100 --json headSha,conclusion,databaseId \
            --jq '.[] | "\(.headSha) \(.conclusion) \(.databaseId)"' | grep -Ff <(printf '%s\n' "$commits") | head -1 || true)
    read -r rsha c rid <<< "${run:-x none x}"
    [ "$c" = success ] || die "the newest $wf run on ${at:0:7}..${sha:0:7} is '$c' (${rid}), not success"
    echo "ok    $wf: run $rid on ${rsha:0:7} (paths last changed in ${at:0:7}): success"
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
