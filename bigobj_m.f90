module bigobj_m

  use bigobj_h
  use log_m
  use const_numphys_h
  use const_kind_m
  use misc_m

  implicit none
  private

! public subroutines
  public :: &
  bigobj_initfile,  & !< open file
  bigobj_readcon,  & !< read data from file
  bigobj_solve,  & !< generic subroutine
  bigobj_userdefined,  & !< user-defined function
  bigobj_fn, &  !< general external function call
  bigobj_dia, &  !< object diagnostics to log file
  bigobj_initwrite, & !< open new file, making up name
  bigobj_write, &  !< write out object
  bigobj_writeg, &  !< write out object as gnuplot
  bigobj_writev, &  !< write out object as vtk
  bigobj_delete, & !< delete object
  bigobj_close, & !< close file
  bigobj_closewrite !< close write file

! private variables
  character(*), parameter :: m_name='bigobj_m' !< module name
  integer(ki4)  :: status   !< error status
  integer(ki4), save  :: ninbo=5     !< control file unit number
  integer(ki4), save  :: noutbo=6      !< output file unit number
  character(len=80), save :: controlfile !< control file name
  character(len=80), save :: outputfile !< output file name
  integer(ki4) :: i !< loop counter
  integer(ki4) :: j !< loop counter
  integer(ki4) :: k !< loop counter
  integer(ki4) :: l !< loop counter
  integer(ki4) :: ij !< loop counter
  integer(ki4)  :: ilog      !< for namelist dump after error

  contains
!---------------------------------------------------------------------
!> open file
subroutine bigobj_initfile(file,channel)

  !! arguments
  character(*), intent(in) :: file !< file name
  integer(ki4), intent(out),optional :: channel   !< input channel for object data structure
  !! local
  character(*), parameter :: s_name='bigobj_initfile' !< subroutine name
  logical :: unitused !< flag to test unit is available

  if (trim(file)=='null') then
     call log_error(m_name,s_name,1,log_info,'null filename ignored')
     return
  end if

! get file unit do i=99,1,-1 inquire(i,opened=unitused) if(.not.unitused)then ninbo=i if (present(channel)) channel=i exit end if end do

  call misc_getfileunit(ninbo)
  if (present(channel)) channel=ninbo

  !! open file
  controlfile=trim(file)
  call log_value("Control data file",trim(controlfile))
  open(unit=ninbo,file=controlfile,status='OLD',iostat=status)
  if(status/=0)then
     !! error opening file
     print '("Fatal error: Unable to open control file, ",a)',controlfile
     call log_error(m_name,s_name,2,error_fatal,'Cannot open control data file')
     stop
  end if

end subroutine bigobj_initfile
!---------------------------------------------------------------------
!> read data from file
subroutine bigobj_readcon(selfn,channel)

  !! arguments
  type(bonumerics_t), intent(out) :: selfn !< type which data will be assigned to
  integer(ki4), intent(in),optional :: channel   !< input channel for object data structure

  !! local
  character(*), parameter :: s_name='bigobj_readcon' !< subroutine name
  character(len=80) :: bigobj_formula !< formula to be used
  integer(ki4), parameter :: MAX_NUMBER_OF_PARAMETERS=10 !< maximum number of parameters allowed
  real(kr8) :: power_split !< variable with meaningful name

  real(kr8), dimension(MAX_NUMBER_OF_PARAMETERS) :: general_real_parameters  !< local variable
  integer(ki4), dimension(MAX_NUMBER_OF_PARAMETERS) :: general_integer_parameters  !< local variable
  integer(ki4) :: number_of_real_parameters  !< local variable
  integer(ki4) :: number_of_integer_parameters  !< local variable

  !! bigobj parameters
  namelist /bigobjparameters/ &
 &power_split, bigobj_formula, &
 &general_real_parameters, number_of_real_parameters, &
 &general_integer_parameters, number_of_integer_parameters

  !! set default bigobj parameters
  power_split=0.5_kr8

  bigobj_formula='unset'
  general_real_parameters=0
  general_integer_parameters=0
  number_of_real_parameters=0
  number_of_integer_parameters=0

  if(present(channel).AND.channel/=0) then
     !! assume unit already open and reading infile
     ninbo=channel
  end if

  !!read bigobj parameters
  read(ninbo,nml=bigobjparameters,iostat=status)
  if(status/=0) then
     !!dump namelist contents to logfile to assist error location
     print '("Fatal error reading bigobj parameters")'
     call log_getunit(ilog)
     write(ilog,nml=bigobjparameters)
     call log_error(m_name,s_name,1,error_fatal,'Error reading bigobj parameters')
  end if

  call lowor(bigobj_formula,1,len_trim(bigobj_formula))
  !! check for valid data

  formula_chosen: select case (bigobj_formula)
  case('unset','exp')
     if(power_split<0.OR.power_split>1) &
 &   call log_error(m_name,s_name,11,error_fatal,'power_split must be >=0 and <=1')

  case('expdouble')
     if(power_split<0.OR.power_split>1) &
 &   call log_error(m_name,s_name,21,error_fatal,'power_split must be >=0 and <=1')

  case('userdefined','additional')
     if(number_of_real_parameters<0) &
 &   call log_error(m_name,s_name,44,error_fatal,'number of real parameters must be >=0')
     if(number_of_real_parameters>MAX_NUMBER_OF_PARAMETERS) then
        call log_value("max number of real parameters",MAX_NUMBER_OF_PARAMETERS)
        call log_error(m_name,s_name,45,error_fatal,'too many parameters: increase MAX_NUMBER_OF_PARAMETERS')
     end if
     if(number_of_integer_parameters<0) &
 &   call log_error(m_name,s_name,46,error_fatal,'number of integer parameters must be >=0')
     if(number_of_integer_parameters>MAX_NUMBER_OF_PARAMETERS) then
        call log_value("max number of integer parameters",MAX_NUMBER_OF_PARAMETERS)
        call log_error(m_name,s_name,47,error_fatal,'too many parameters: increase MAX_NUMBER_OF_PARAMETERS')
     end if
     if(number_of_integer_parameters==0.AND.number_of_real_parameters==0) &
 &   call log_error(m_name,s_name,48,error_fatal,'no parameters set')

  end select formula_chosen

  !! store values
  selfn%formula=bigobj_formula

  selfn%f=power_split

  !! allocate arrays and assign

  selfn%nrpams=number_of_real_parameters
  selfn%nipams=number_of_integer_parameters

  formula_allocate: select case (bigobj_formula)

  case('userdefined','additional')
     if (number_of_real_parameters>0) then
        allocate(selfn%rpar(number_of_real_parameters), stat=status)
        call log_alloc_check(m_name,s_name,65,status)
        selfn%rpar=general_real_parameters(:number_of_real_parameters)
     end if
     if (number_of_integer_parameters>0) then
        allocate(selfn%npar(number_of_integer_parameters), stat=status)
        call log_alloc_check(m_name,s_name,66,status)
        selfn%npar=general_integer_parameters(:number_of_integer_parameters)
     end if
  case default
  end select formula_allocate

end  subroutine bigobj_readcon
!---------------------------------------------------------------------
!> generic subroutine
subroutine bigobj_solve(self)

  !! arguments
  type(bigobj_t), intent(inout) :: self !< module object
  !! local
  character(*), parameter :: s_name='bigobj_solve' !< subroutine name

  self%pow=bigobj_fn(self,0._kr8)

end subroutine bigobj_solve
!---------------------------------------------------------------------
!> output to log file
subroutine bigobj_dia(self)

  !! arguments
  type(bigobj_t), intent(inout) :: self !< module object
  !! local
  character(*), parameter :: s_name='bigobj_dia' !< subroutine name

  call log_value("power ",self%pow)

end subroutine bigobj_dia
!---------------------------------------------------------------------
!> userdefined function
function bigobj_userdefined(self,psi)

  !! arguments
  type(bigobj_t), intent(in) :: self !< module object
  real(kr8) :: bigobj_userdefined !< local variable
  real(kr8), intent(in) :: psi !< position in \f$ \psi \f$

  !! local variables
  character(*), parameter :: s_name='bigobj_userdefined' !< subroutine name
  real(kr8) :: pow !< local variable
  real(kr8) :: zpos !< position
  integer(ki4) :: ilocal !< local integer variable

  zpos=psi
  pow=0._kr8
  !> user defines \Tt{pow} here
  !! .....
  !! return bigobj
  bigobj_userdefined=pow

end function bigobj_userdefined
!---------------------------------------------------------------------
!> general external function call
function bigobj_fn(self,psi)

  !! arguments
  type(bigobj_t), intent(in) :: self !< module object
  real(kr8) :: bigobj_fn !< local variable
  real(kr8), intent(in) :: psi !< position in \f$ \psi \f$

  !! local variables
  character(*), parameter :: s_name='bigobj_fn' !< subroutine name
  real(kr8) :: pow !< local variable

  pow=0._kr8
  !! select bigobj
  formula_chosen: select case (self%n%formula)
  case('userdefined','additional')
     pow=bigobj_userdefined(self,psi)
  end select formula_chosen

  !! return bigobj
  bigobj_fn=pow

end function bigobj_fn
!---------------------------------------------------------------------
!> open new file, making up name
subroutine bigobj_initwrite(fileroot,channel)

  !! arguments
  character(*), intent(in) :: fileroot !< file root
  integer(ki4), intent(out),optional :: channel   !< output channel for object data structure
  !! local
  character(*), parameter :: s_name='bigobj_initwrite' !< subroutine name
  logical :: unitused !< flag to test unit is available
  character(len=80) :: outputfile !< output file name

! get file unit do i=99,1,-1 inquire(i,opened=unitused) if(.not.unitused)then if (present(channel)) channel=i exit end if end do noutbo=i

  call misc_getfileunit(noutbo)
  if (present(channel)) channel=noutbo

  !! open file
  outputfile=trim(fileroot)//"_bigobj.out"
  call log_value("Control data file",trim(outputfile))
  open(unit=noutbo,file=outputfile,status='NEW',iostat=status)
  if(status/=0)then
     open(unit=noutbo,file=outputfile,status='REPLACE',iostat=status)
  end if
  if(status/=0)then
     !! error opening file
     print '("Fatal error: Unable to open output file, ",a)',outputfile
     call log_error(m_name,s_name,1,error_fatal,'Cannot open output data file')
     stop
  end if

end subroutine bigobj_initwrite
!---------------------------------------------------------------------
!> write bigobj data
subroutine bigobj_write(self,channel)

  !! arguments
  type(bigobj_t), intent(in) :: self   !< bigobj data structure
  integer(ki4), intent(in), optional :: channel   !< output channel for bigobj data structure

  !! local
  character(*), parameter :: s_name='bigobj_write' !< subroutine name
  integer(ki4) :: iout   !< output channel for bigobj data structure

  !! sort out unit
  if(present(channel)) then
     iout=channel
  else
     iout=noutbo
  end if

  write(iout,*,iostat=status) 'bigobj_formula'
  call log_write_check(m_name,s_name,18,status)
  write(iout,*,iostat=status) self%n%formula
  call log_write_check(m_name,s_name,19,status)
  write(iout,*,iostat=status) 'f'
  call log_write_check(m_name,s_name,20,status)
  write(iout,*,iostat=status) self%n%f
  call log_write_check(m_name,s_name,21,status)
  write(iout,*,iostat=status) 'nrpams'
  call log_write_check(m_name,s_name,46,status)
  write(iout,*,iostat=status) self%n%nrpams
  call log_write_check(m_name,s_name,47,status)
  if (self%n%nrpams>0) then
     write(iout,*,iostat=status) 'real_parameters'
     call log_write_check(m_name,s_name,48,status)
     write(iout,*,iostat=status) self%n%rpar
     call log_write_check(m_name,s_name,49,status)
  end if
  write(iout,*,iostat=status) 'nipams'
  call log_write_check(m_name,s_name,50,status)
  write(iout,*,iostat=status) self%n%nipams
  call log_write_check(m_name,s_name,51,status)
  if (self%n%nipams>0) then
     write(iout,*,iostat=status) 'integer_parameters'
     call log_write_check(m_name,s_name,52,status)
     write(iout,*,iostat=status) self%n%npar
     call log_write_check(m_name,s_name,53,status)
  end if

end subroutine bigobj_write
!---------------------------------------------------------------------
!> write object data as gnuplot
subroutine bigobj_writeg(self,select,channel)

  !! arguments
  type(bigobj_t), intent(in) :: self   !< object data structure
  character(*), intent(in) :: select  !< case
  integer(ki4), intent(in), optional :: channel   !< output channel for bigobj data structure

  !! local
  character(*), parameter :: s_name='bigobj_writeg' !< subroutine name
  integer(ki4) :: iout   !< output channel for bigobj data structure

  call log_error(m_name,s_name,1,log_info,'gnuplot file produced')

  plot_type: select case(select)
  case('cartesian')

  case default

  end select plot_type

end subroutine bigobj_writeg
!---------------------------------------------------------------------
!> write object data as vtk
subroutine bigobj_writev(self,select,channel)

  !! arguments
  type(bigobj_t), intent(in) :: self   !< object data structure
  character(*), intent(in) :: select  !< case
  integer(ki4), intent(in), optional :: channel   !< output channel for bigobj data structure

  !! local
  character(*), parameter :: s_name='bigobj_writev' !< subroutine name
  integer(ki4) :: iout   !< output channel for bigobj data structure

  call log_error(m_name,s_name,1,log_info,'vtk file produced')

  plot_type: select case(select)
  case('cartesian')

  case default

  end select plot_type

end subroutine bigobj_writev
!---------------------------------------------------------------------
!> close write file
subroutine bigobj_closewrite

  !! local
  character(*), parameter :: s_name='bigobj_closewrite' !< subroutine name

  !! close file
  close(unit=noutbo,iostat=status)
  if(status/=0)then
     !! error closing file
     print '("Fatal error: Unable to close output file, ",a)',outputfile
     call log_error(m_name,s_name,1,error_fatal,'Cannot close output data file')
     stop
  end if

end subroutine bigobj_closewrite
!---------------------------------------------------------------------
!> delete object
subroutine bigobj_delete(self)

  !! arguments
  type(bigobj_t), intent(inout) :: self !< module object
  !! local
  character(*), parameter :: s_name='bigobj_delete' !< subroutine name

  formula_deallocate: select case (self%n%formula)
  case('userdefined','additional')
     if (self%n%nrpams>0) deallocate(self%n%rpar)
     if (self%n%nipams>0) deallocate(self%n%npar)
  case default
  end select formula_deallocate

end subroutine bigobj_delete
!---------------------------------------------------------------------
!> close file
subroutine bigobj_close

  !! local
  character(*), parameter :: s_name='bigobj_close' !< subroutine name

  !! close file
  close(unit=ninbo,iostat=status)
  if(status/=0)then
     !! error closing file
     print '("Fatal error: Unable to close control file, ",a)',controlfile
     call log_error(m_name,s_name,1,error_fatal,'Cannot close control data file')
     stop
  end if

end subroutine bigobj_close

end module bigobj_m
