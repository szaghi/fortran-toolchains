!< The fixture of the release and installer workflows with a dependency (fortran-toolchains#3): it uses PENF.
module fixture_deps
use penf, only : I4P
implicit none
private
public :: twice

contains
   pure function twice(n) result(m)
   !< Twice n.
   integer(I4P), intent(in) :: n !< The input.
   integer(I4P)             :: m !< Twice n.

   m = 2_I4P * n
   endfunction twice
endmodule fixture_deps
