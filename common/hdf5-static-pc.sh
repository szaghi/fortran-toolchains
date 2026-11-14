#!/usr/bin/env bash
# The pkg-config files of a static-only HDF5 install (build-hdf5.sh) completed with their private libraries: with no
# shared library, `Libs.private` (hdf5_f90cstub; m, dl, z) is the link line, and a consumer calling pkg-config without
# --static (fpm's hdf5 metapackage) links nothing else. Idempotent (the macOS setup runs it on a cached prefix too);
# portable to bash 3.2 and BSD sed (no sed -i).
#
#   hdf5-static-pc.sh <hdf5 prefix>
set -euo pipefail
prefix=${1:?usage: hdf5-static-pc.sh <hdf5 prefix>}
for pc in "$prefix"/lib/pkgconfig/*.pc; do
  [ -f "$pc" ] || continue
  priv=$(sed -n 's/^Libs.private: *//p' "$pc" | sed 's/ *$//')
  [ -n "$priv" ] || continue
  libs=$(sed -n 's/^Libs: *//p' "$pc" | sed 's/ *$//')
  case " $libs " in *" $priv "*|*" $priv") continue ;; esac   # done before
  sed "s|^Libs: .*|Libs: $libs $priv|" "$pc" > "$pc.tmp" && mv "$pc.tmp" "$pc"
  echo "hdf5-static-pc.sh: ${pc##*/}: Libs: $libs $priv"
done
