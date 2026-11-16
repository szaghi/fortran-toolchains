#!/usr/bin/env bash
# One build of a release through its one-line installer (interface 2, FoBiS#217), as install.yml runs it on a fresh
# runner (fortran-toolchains#3), and checks what it installed:
#
#   install-check.sh INSTALLER BUILD PREFIX [installer options...]     (e.g. --tag v1.2.3 --fc gfortran-16, --source DIR)
#
# 1. the installer runs with --build BUILD --prefix PREFIX, FoBiS taken off PATH: the installer must bootstrap it when
#    BUILD (or the project's [installer] rules) needs it, as on a user's machine;
# 2. every pkg-config file it wrote resolves (pkg-config --cflags --libs), each -L directory holds each -l library,
#    each -I directory holds module files;
# 3. --uninstall leaves no file in PREFIX but the installer's FoBiS venv.
set -uo pipefail

[ $# -ge 3 ] || { echo "usage: $0 INSTALLER BUILD PREFIX [installer options...]" >&2; exit 2; }
installer=$1 build=$2 prefix=$3; shift 3
case $prefix in /*) ;; *) prefix="$(pwd)/$prefix" ;; esac

# FoBiS off PATH: every directory holding a fobis or FoBiS.py executable
path=''
IFS=: read -r -a dirs <<< "$PATH"
for d in "${dirs[@]}"; do
  if [ -x "$d/fobis" ] || [ -x "$d/FoBiS.py" ]; then continue; fi
  path="${path:+$path:}$d"
done

echo "== install.sh --build $build --prefix $prefix $*"
PATH=$path bash "$installer" --build "$build" --prefix "$prefix" "$@" || { echo "::error::install.sh --build $build failed"; exit 1; }

fails=0
pcdir="$prefix/lib/pkgconfig"
pcs=$(find "$pcdir" -maxdepth 1 -name '*.pc' 2> /dev/null | sort)
[ -n "$pcs" ] || { echo "::error::--build $build wrote no pkg-config file in $pcdir"; exit 1; }
for pc in $pcs; do
  pkg=$(basename "$pc" .pc)
  flags=$(PKG_CONFIG_PATH=$pcdir pkg-config --cflags --libs "$pkg") || { echo "::error::pkg-config $pkg fails"; fails=1; continue; }
  echo "$pkg: $flags"
  libdirs=''; libs=''; incdirs=''
  for f in $flags; do
    case $f in
      -L*) libdirs="$libdirs ${f#-L}" ;;
      -l*) libs="$libs ${f#-l}" ;;
      -I*) incdirs="$incdirs ${f#-I}" ;;
    esac
  done
  for l in $libs; do
    found=0; for d in $libdirs; do ls "$d/lib$l".* > /dev/null 2>&1 && found=1; done
    [ "$found" = 1 ] || { echo "::error::$pkg: -l$l in none of$libdirs"; fails=1; }
  done
  for d in $incdirs; do
    ls "$d"/*.mod > /dev/null 2>&1 || { echo "::error::$pkg: -I$d holds no module file"; fails=1; }
  done
done

echo "== install.sh --uninstall --prefix $prefix"
PATH=$path bash "$installer" --uninstall --prefix "$prefix" || { echo "::error::--uninstall failed"; fails=1; }
left=$(find "$prefix" -type f -not -path '*/venv/*' 2> /dev/null)
[ -z "$left" ] || { echo "::error::--uninstall left files:"; echo "$left"; fails=1; }

[ "$fails" = 0 ] && echo "ok: --build $build installed, resolved by pkg-config, uninstalled"
exit "$fails"
