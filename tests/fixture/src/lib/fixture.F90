!< The library of the fixture project: a sum, and a description of the compiler that built it.
module fixture
use, intrinsic :: iso_fortran_env, only : compiler_version, int32
implicit none
private
public :: sum_to, built_by

contains
  pure function sum_to(n) result(s)
  !< The sum of the integers 1 to n (0 for n < 1).
  integer(int32), intent(in) :: n !< Last integer.
  integer(int32)             :: s !< The sum.
  integer(int32)             :: i

  s = 0
  do i = 1, n
    s = s + i
  enddo
  endfunction sum_to

  function built_by() result(description)
  !< The compiler that built the library.
  character(:), allocatable :: description !< Its version string.

  description = compiler_version()
  endfunction built_by
endmodule fixture
