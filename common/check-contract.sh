#!/usr/bin/env bash
# The environment contract every toolchain exports, image or setup action, Linux, macOS or Windows (MSYS2): run at
# build time in every image flavour and at the end of every setup action. Portable to bash 3.2 (macOS's /bin/bash).
#
#   check-contract.sh          FC CC CXX TOOLCHAIN TOOLCHAIN_OS TOOLCHAIN_FAMILY set and sane; FC and CC build and run
#                              a program, CXX compiles one; fobis, fpm, python3 (>= 3.11), cmake, ninja, pkg-config on PATH
#   check-contract.sh --mpi    also MPIFC, MPIRUN and HDF5_ROOT (the full flavour): MPIFC builds a program that uses
#                              mpi_f08 and hdf5 against $HDF5_ROOT, MPIRUN runs it on 2 ranks
#
# Exit 1 on any failure; every check prints one line.
set -uo pipefail

fail=0
ok()  { printf 'ok    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }
var() { eval "printf '%s' \"\${$1:-}\""; }   # bash 3.2-safe indirect expansion with a default

work=$(mktemp -d 2>/dev/null || mktemp -d -t contract)
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1

required="FC CC CXX TOOLCHAIN TOOLCHAIN_OS TOOLCHAIN_FAMILY"
[ "${1:-}" = --mpi ] && required="$required MPIFC MPIRUN HDF5_ROOT"
for v in $required; do
  if [ -n "$(var "$v")" ]; then ok "$v=$(var "$v")"; else bad "$v is not set"; fi
done

case ${TOOLCHAIN_OS:-} in linux|macos|windows) ;; *) bad "TOOLCHAIN_OS='${TOOLCHAIN_OS:-}' is not linux, macos or windows" ;; esac
case ${TOOLCHAIN_FAMILY:-} in gnu|nvf|intel) ;; *) bad "TOOLCHAIN_FAMILY='${TOOLCHAIN_FAMILY:-}' is not gnu, nvf or intel" ;; esac
case ${TOOLCHAIN:-} in "${TOOLCHAIN_OS:-}"-*) ;; *) bad "TOOLCHAIN='${TOOLCHAIN:-}' does not start with '${TOOLCHAIN_OS:-}-'" ;; esac

# the compilers: a Fortran and a C program built and run, a C++ one compiled
printf 'program p\nprint "(a)", "fortran ok"\nend program p\n' > p.f90
if "${FC:-false}" p.f90 -o pf >/dev/null 2>&1 && ./pf | grep -q 'fortran ok'; then ok "FC builds and runs a program"
else bad "FC (${FC:-unset}) cannot build and run a program"; fi
printf '#include <stdio.h>\nint main(void) { puts("c ok"); return 0; }\n' > p.c
if "${CC:-false}" p.c -o pc >/dev/null 2>&1 && ./pc | grep -q 'c ok'; then ok "CC builds and runs a program"
else bad "CC (${CC:-unset}) cannot build and run a program"; fi
printf 'int main() { return 0; }\n' > p.cpp
if "${CXX:-false}" -c p.cpp -o pcpp.o >/dev/null 2>&1; then ok "CXX compiles a program"
else bad "CXX (${CXX:-unset}) cannot compile a program"; fi

# the tools
for t in fobis fpm python3 cmake ninja pkg-config; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t: $(command -v "$t")"; else bad "$t is not on PATH"; fi
done
if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
  ok "python3 >= 3.11 ($(python3 -c 'import platform; print(platform.python_version())'))"
else bad "python3 is missing or older than 3.11"; fi

# MPI and HDF5
if [ "${1:-}" = --mpi ]; then
  cat > m.f90 <<'EOF'
program m
use mpi_f08
use hdf5
implicit none
integer :: rank, error
call MPI_Init()
call MPI_Comm_rank(MPI_COMM_WORLD, rank)
call h5open_f(error)
if (error /= 0) error stop 1
call h5close_f(error)
if (rank == 0) print '(a)', 'mpi ok'
call MPI_Finalize()
end program m
EOF
  if "${MPIFC:-false}" -I"${HDF5_ROOT:-}/include" m.f90 -o pm \
       -L"${HDF5_ROOT:-}/lib" -lhdf5_fortran -lhdf5_f90cstub -lhdf5 -lz -ldl -lm >/dev/null 2>&1; then
    ok "MPIFC builds a program using mpi_f08 and hdf5 (HDF5_ROOT)"
    if "${MPIRUN:-false}" -np 2 ./pm 2>/dev/null | grep -q 'mpi ok'; then ok "MPIRUN runs it on 2 ranks"
    else bad "MPIRUN (${MPIRUN:-unset}) cannot run it on 2 ranks"; fi
  else
    bad "MPIFC (${MPIFC:-unset}) cannot build a program using mpi_f08 and hdf5 against HDF5_ROOT (${HDF5_ROOT:-unset})"
  fi
fi

exit $fail
