!< Test of fixture's sum_to against Gauss' formula.
program fixture_test_sum
use, intrinsic :: iso_fortran_env, only : int32
use fixture, only : sum_to, built_by
implicit none
integer(int32) :: n
logical        :: passed

passed = sum_to(0) == 0
do n = 1, 100
  passed = passed .and. sum_to(n) == n * (n + 1) / 2
enddo
print '(A)', 'built by: '//built_by()
print '(A,L1)', 'Are all tests passed? ', passed
if (.not.passed) error stop 1
endprogram fixture_test_sum
