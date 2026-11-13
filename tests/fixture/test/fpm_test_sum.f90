!< The fpm test of the fixture: sum_to against Gauss' formula.
program fpm_test_sum
use fixture, only : sum_to
implicit none
integer :: n

do n = 1, 100
  if (sum_to(n) /= n * (n + 1) / 2) error stop 1
enddo
print '(A)', 'fpm test: passed'
endprogram fpm_test_sum
