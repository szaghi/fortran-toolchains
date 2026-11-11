!< Toolchain check, run at image build time on 2 ranks: mpi_f08 and the hdf5 module read by this gfortran, a parallel
!< HDF5 file written collectively by the ranks, the deflate filter available. Exit status non-zero on any failure.
program check
use mpi_f08
use hdf5
implicit none
integer          :: rank, nranks, error
integer(hid_t)   :: fapl, file_id, space, dset, memspace, dxpl
integer(hsize_t) :: dims(1), start(1), count(1)
integer          :: values(4)
logical          :: deflate

call MPI_Init()
call MPI_Comm_rank(MPI_COMM_WORLD, rank)
call MPI_Comm_size(MPI_COMM_WORLD, nranks)
call h5open_f(error)                                                ; call ok(error, 'h5open_f')
call h5zfilter_avail_f(H5Z_FILTER_DEFLATE_F, deflate, error)        ; call ok(error, 'h5zfilter_avail_f')
if (.not.deflate) call ok(1, 'the deflate filter')
call h5pcreate_f(H5P_FILE_ACCESS_F, fapl, error)                    ; call ok(error, 'h5pcreate_f')
call h5pset_fapl_mpio_f(fapl, MPI_COMM_WORLD, MPI_INFO_NULL, error) ; call ok(error, 'h5pset_fapl_mpio_f')
call h5fcreate_f('check.h5', H5F_ACC_TRUNC_F, file_id, error, access_prp=fapl) ; call ok(error, 'h5fcreate_f')
dims = 4 * nranks
call h5screate_simple_f(1, dims, space, error)                      ; call ok(error, 'h5screate_simple_f')
call h5dcreate_f(file_id, 'ranks', H5T_NATIVE_INTEGER, space, dset, error) ; call ok(error, 'h5dcreate_f')
start = 4 * rank ; count = 4
call h5sselect_hyperslab_f(space, H5S_SELECT_SET_F, start, count, error) ; call ok(error, 'h5sselect_hyperslab_f')
call h5screate_simple_f(1, count, memspace, error)                  ; call ok(error, 'h5screate_simple_f')
call h5pcreate_f(H5P_DATASET_XFER_F, dxpl, error)                   ; call ok(error, 'h5pcreate_f')
call h5pset_dxpl_mpio_f(dxpl, H5FD_MPIO_COLLECTIVE_F, error)        ; call ok(error, 'h5pset_dxpl_mpio_f')
values = rank
call h5dwrite_f(dset, H5T_NATIVE_INTEGER, values, count, error, memspace, space, dxpl) ; call ok(error, 'h5dwrite_f')
call h5pclose_f(dxpl, error) ; call h5sclose_f(memspace, error) ; call h5sclose_f(space, error)
call h5dclose_f(dset, error) ; call h5pclose_f(fapl, error)
call h5fclose_f(file_id, error)                                     ; call ok(error, 'h5fclose_f')
call h5close_f(error)
if (rank == 0) print '(A,I0,A)', 'toolchain check: ', nranks, ' ranks wrote check.h5 (parallel HDF5, deflate available)'
call MPI_Finalize()
contains
  subroutine ok(error, what)
  !< Stop with an error if `error` is not zero.
  integer,      intent(in) :: error
  character(*), intent(in) :: what

  if (error /= 0) then
    print '(A)', 'toolchain check failed: '//what
    error stop 1
  endif
  endsubroutine ok
endprogram check
