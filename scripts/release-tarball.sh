#!/usr/bin/env bash
# The release tarball of a project, <name>-<tag>.tar.gz, as release.yml publishes it (fortran-toolchains#3): run in
# the project's directory of a fresh checkout.
#
#   release-tarball.sh NAME TAG OUTDIR [--bundle] [--excludes "PATTERN ..."]
#
# The tarball holds every non-hidden top-level entry (not .git, .github, .fortran-toolchains), under NAME-TAG/, without
# the --excludes patterns (tar --exclude: a pattern matches a path component at any depth). With --bundle and a fobos
# [dependencies] section, the dependencies are fetched first (fobis fetch --no-build) and bundled: CMake and make
# builds of the release then need neither FoBiS nor a network. The dependencies' directory is bundled even when it is
# hidden (.fobis_deps, FoBiS's default), their .git directories never. fobis comes from PATH, else a venv with FoBiS at
# $FOBIS (a version, from versions.env). The bundled dependencies and their commits (fobos.lock) are listed on stdout
# and in $GITHUB_STEP_SUMMARY when set.
set -euo pipefail

[ $# -ge 3 ] || { echo "usage: $0 NAME TAG OUTDIR [--bundle] [--excludes \"PATTERN ...\"]" >&2; exit 2; }
name=$1 tag=$2 out=$3; shift 3
bundle=0 excludes=''
while [ $# -gt 0 ]; do
  case $1 in
    --bundle) bundle=1; shift ;;
    --excludes) excludes=$2; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$out"

extra=()
if [ "$bundle" = 1 ] && [ -f fobos ] && grep -q '^\[dependencies\]' fobos; then
  if ! command -v fobis > /dev/null; then
    python3 -m venv "${RUNNER_TEMP:-/tmp}/release-fobis"
    "${RUNNER_TEMP:-/tmp}/release-fobis/bin/pip" install --quiet "FoBiS.py${FOBIS:+==$FOBIS}"
    PATH="${RUNNER_TEMP:-/tmp}/release-fobis/bin:$PATH"
  fi
  fobis fetch --no-build
  # the project's dependencies directory: where fetch wrote .deps_config.ini, the shallowest one
  config=$(find . -name .deps_config.ini -not -path './.git/*' | awk '{ print length($0) " " $0 }' | sort -n \
    | sed -n '1s/^[0-9]* //p')
  [ -n "$config" ] || { echo "release-tarball: fobis fetch wrote no .deps_config.ini" >&2; exit 1; }
  deps=$(dirname "${config#./}")
  case $deps in .*) extra+=("$deps") ;; esac   # a hidden directory: the * glob below would leave it out
  {
    echo "### Bundled dependencies ($deps)"
    if [ -f "$deps/fobos.lock" ]; then
      awk '/^\[/ { n = substr($0, 2, length($0) - 2) } /^commit *=/ { print "- " n " " $3 }' "$deps/fobos.lock"
    else
      find "$deps" -mindepth 1 -maxdepth 1 -type d -printf '- %f\n'
    fi
  } | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
fi

args=(--exclude=.git)
for e in $excludes; do args+=("--exclude=$e"); done
# the glob leaves out the dot-directories (.git, .github, .fortran-toolchains)
tar --xform="s%^%$name-$tag/%" -czf "$out/$name-$tag.tar.gz" "${args[@]}" -- * ${extra[@]+"${extra[@]}"}
echo "$out/$name-$tag.tar.gz: $(tar -tzf "$out/$name-$tag.tar.gz" | wc -l) entries"
