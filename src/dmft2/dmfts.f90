MODULE dmfts
  INTEGER :: lmaxp =    0   ! maximum l for projector. Should be set in l2main
  REAL*8  :: DM_Emin, DM_Emax, DM_EF, gammac, gamma, aom_default, bom_default, mixEF, Temperature, wl
  INTEGER :: iso
  LOGICAL :: matsubara, Qcomplex, Qrenormalize
  INTEGER :: projector, nom_default, natom
  INTEGER, ALLOCATABLE :: nl(:), ll(:,:), qsplit(:,:), cix(:,:), iatom(:), shft(:,:), isort(:)
  REAL*8,  ALLOCATABLE :: crotloc(:,:,:)
  CHARACTER*1 :: mode
  INTEGER :: ncix, maxdim, maxsize, ntcix
  INTEGER :: wndim  ! We should probably have different wndim for each cix!
  COMPLEX*16, ALLOCATABLE :: CF(:,:,:)
  INTEGER, ALLOCATABLE :: Sigind(:,:,:), csize(:), Sigind_orig(:,:,:)
  CHARACTER*30, ALLOCATABLE :: legend(:,:)
  LOGICAL :: Q_ETOT
  INTEGER :: recomputeEF
CONTAINS
  SUBROUTINE Read_indmf2(fh)
    ! Reads input file case.indmf2
    IMPLICIT NONE
    INTEGER, intent(in) :: fh  ! should be 2
    ! locals
    REAL*8,PARAMETER       :: Ry2eV= 13.60569253d0
    
    READ(fh,*) ! comment: mode and the current chemical potential
    READ(fh,*) mode, DM_EF, recomputeEF, mixEF, Q_ETOT, Temperature
    DM_EF = DM_EF/Ry2eV
    WL=1.0
    IF (recomputeEF.GT.1) THEN
       READ(fh,*) WL
    ENDIF
    WL = WL/Ry2eV
  END SUBROUTINE Read_indmf2

  SUBROUTINE Read_indmfl(fhr, fh_stdout, nemin0, nemax0, loro, rotloc, mult, nat, natm, Qprint)
    ! Reads input file case.indmfl
    IMPLICIT NONE
    INTEGER, intent(in) :: fhr, fh_stdout  ! fhr should be 7, fh_stdout should be 6
    INTEGER, intent(in) :: nat, natm, mult(nat)
    INTEGER, intent(out):: nemin0, nemax0, loro
    REAL*8, intent(in)  :: rotloc(3,3,nat)
    LOGICAL, intent(in) :: Qprint ! should be myrank.EQ.master .OR. fastFilesystem
    ! locals
    REAL*8,PARAMETER    :: Ry2eV= 13.60569253d0
    INTEGER :: irenormalize, imatsubara, wat, i, j, j1, shift, icix, size, ident, m1, m2
    INTEGER :: latom, jatom, locrot, wicix, minsigind, wfirst, iat, im
    REAL*8  :: xx(3), xz(3), thetaz, phiz, thetax, phix, ddd, check
    REAL*8, allocatable :: wtmpx(:)
    LOGICAL :: Qident
    
    READ(fhr,*) DM_Emin,DM_Emax,irenormalize,projector

    if (irenormalize.EQ.0) then
       Qrenormalize = .FALSE.
    else
       Qrenormalize = .TRUE.
    endif
    
    if (abs(projector).lt.4) then
       DM_Emin = DM_Emin/Ry2eV
       DM_Emax = DM_Emax/Ry2eV
       if (Qprint) WRITE(fh_stdout,'(A,1x,f15.10,1x,f15.10)') 'Emin,Emax=', DM_Emin, DM_Emax
    else
       nemin0=int(DM_Emin)
       nemax0=int(DM_Emax)
       if (Qprint) WRITE(fh_stdout,'(A,1x,I6,1x,I6)') 'nemin,nemax=', nemin0, nemax0
    endif
  
    READ(fhr,*) imatsubara, gammac, gamma, nom_default, aom_default, bom_default
    if (imatsubara.EQ.0) then
       matsubara = .FALSE.
    else
       matsubara = .TRUE.
    endif
    if (Qprint) WRITE(fh_stdout,'(A,I2,1x,A,f10.5,1x,A,f10.5,1x)') 'imatsubara=', imatsubara, 'gammac=', gammac, 'gamma=', gamma
    read(fhr,*) natom
  
    ALLOCATE(nl(natom))
    allocate(ll(natom,4), qsplit(natom,4), cix(natom,4), iatom(natom))
    ALLOCATE(crotloc(3,3,natom))

    crotloc=0
    ALLOCATE( isort(natm) )
    wfirst  = 1          ! first atom of this particular sort
    do iat=1,nat         ! over all sorts
       do im=1,MULT(iat) ! over all atoms of this sort
          wat = wfirst + im-1  ! atom number
          isort(wat)=iat       ! sort of each atom
       enddo
       wfirst = wfirst + MULT(iat)
    enddo

    ALLOCATE(shft(natm,3) )
    shft = 0
    ll(:,:)=0
    cix(:,:)=0
    iatom(:)=0
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!
    DO i=1,natom
       READ(fhr,*) latom, nl(i), locrot ! read from case.inq
       iatom(i) = latom       ! The succesive number of atom (all atoms counted)
       jatom = isort(latom)   ! The sort of the atom
       !
       loro = MOD(locrot, 3)
       shift = locrot/3
       !
       if (Qprint) WRITE(fh_stdout,'(A,I2,A)'), '--------- atom ', i, ' -------------'

       ! loro can be (0 -original coordinate system), (1 - new z-axis), (2 - new z-axis, x-axis)
       do j=1,nl(i)
          read(fhr,*) ll(i,j), qsplit(i,j), cix(i,j) ! LL contains all L-quantum numbers which need to be computed.
       enddo
       
       do j=1,nl(i)
          if (Qprint) write(fh_stdout, '(A,I3,2x,A,I3)') 'l=', ll(i,j), 'qsplit=', qsplit(i,j)
       enddo
       if (Qprint) write(fh_stdout,*)'No symmetrization over eq. k-points is performed'
       
       crotloc(:,:,i) = rotloc(:,:,jatom)  ! Rotation for this type from the struct file

       ! Rotation matrix in case the coordinate system is changed!
       if(loro.gt.0) then        ! change of local rotation matrix
          read(fhr,*) (xz(j),j=1,3)  ! new z-axis expressed in unit cell vectors
          if (Qprint) write(fh_stdout,120) (xz(j),j=1,3)
          call angle(xz,thetaz,phiz)
          crotloc(1,3,i)=sin(thetaz)*cos(phiz)
          crotloc(2,3,i)=sin(thetaz)*sin(phiz)
          crotloc(3,3,i)=cos(thetaz)          
          if(loro.eq.1) then       ! only z-axis fixed
             crotloc(3,1,i)= 0.     ! new x perpendicular to new z       
             ddd=abs(crotloc(3,3,i)**2-1.)
             if(ddd.gt.0.000001)then
                crotloc(1,1,i)=-crotloc(2,3,i)
                crotloc(2,1,i)= crotloc(1,3,i)
             else
                crotloc(1,1,i)=1.
                crotloc(2,1,i)=0.
             endif
             ddd=0.                 ! normalize new x
             do j=1,3
                ddd=ddd+crotloc(j,1,i)**2
             enddo
             do j=1,3
                crotloc(j,1,i)=crotloc(j,1,i)/sqrt(ddd)
             enddo
          elseif(loro.eq.2) then   ! also new x-axis fixed
             read(fhr,*) (xx(j),j=1,3)
             if (Qprint) write(fh_stdout,121)(xx(j),j=1,3)
             call angle(xx,thetax,phix)
             crotloc(1,1,i)=sin(thetax)*cos(phix)
             crotloc(2,1,i)=sin(thetax)*sin(phix)
             crotloc(3,1,i)=cos(thetax)          
             !  check orthogonality of new x and z axes
             check=0.
             do j=1,3
                check=check+crotloc(j,1,i)*crotloc(j,3,i)
             enddo
             if(abs(check).gt.0.00001)then
                if (Qprint) write(fh_stdout,*)' new x and z axes are not orthogonal'
                print *,' new x and z axes are not orthogonal'
                stop "new x and z axes are not orthogonal"
             endif
          endif
          crotloc(1,2,i)=crotloc(2,3,i)*crotloc(3,1,i)-crotloc(3,3,i)*crotloc(2,1,i)
          crotloc(2,2,i)=crotloc(3,3,i)*crotloc(1,1,i)-crotloc(1,3,i)*crotloc(3,1,i)
          crotloc(3,2,i)=crotloc(1,3,i)*crotloc(2,1,i)-crotloc(2,3,i)*crotloc(1,1,i)
          if (Qprint) then
             write(fh_stdout,*)' New local rotation matrix in global orthogonal system'
             write(fh_stdout,*)'                      new x     new y     new z'
             write(fh_stdout,1013)((crotloc(j,j1,i),j1=1,3),j=1,3)  !written as in .struct
          endif
       elseif (loro.lt.0) then
          read(fhr,*)( crotloc(1,j,i),j=1,3)  ! new x-axis expressed in unit cell vectors
          read(fhr,*)( crotloc(2,j,i),j=1,3)  ! new y-axis expressed in unit cell vectors
          read(fhr,*)( crotloc(3,j,i),j=1,3)  ! new z-axis expressed in unit cell vectors
          if (Qprint) then
             write(fh_stdout,*)' New local rotation matrix in global orthogonal system'
             write(fh_stdout,*)'                      new x     new y     new z'
             write(fh_stdout,1013)((crotloc(j,j1,i),j1=1,3),j=1,3)  !written as in .struct
          endif
       endif   !change of loc.rot. end
       ! end Rotation matrix loro
       
       if (shift.ne.0) then
          read(fhr,*) (shft(latom,j),j=1,3)
          if (Qprint) write(fh_stdout,'(A,1x,I2,A,2x,I3,I3,I3)') '** atom', i, ' has nonzero shift: ', shft(latom,1), shft(latom,2), shft(latom,3)
       endif
    enddo


    READ(fhr,*) ! comment: Next few lines contain instructions (transformation,index) for all correlated orbitals
    READ(fhr,*) ncix, maxdim, maxsize ! number of independent cix blocks
    if (Qprint) WRITE(fh_stdout,*) '********** Start Reading Cix file *************'
    
    ALLOCATE(CF(maxdim,maxdim,ncix))      ! transformation matrix
    ALLOCATE(Sigind(maxdim,maxdim,ncix))  ! correlated index
    ALLOCATE(legend(maxsize, ncix))       ! names of correlated orbitals
    ALLOCATE(csize(ncix))                 ! independent components
    
    ALLOCATE(wtmpx(2*maxdim))              ! temp
  
    ALLOCATE(Sigind_orig(maxdim,maxdim,ncix))  ! correlated index                                                                                                                                                                               

    CF=0
    Sigind=0  
    Qident=.True.
    ntcix=0
    do wicix=1,ncix
       READ(fhr,*) icix, wndim, size  ! icix, size-of-matrix, L, number of independent components of the matrix
       if (wicix.ne.icix) then
          print *, 'Something wrong reading case.indmfl file. Boilig out...'
          CALL OUTERR('dmftdat.f90','Something wrong reading case.indmfl file (1)')
          STOP 'DMFT2 - Error. Check file dmft2.error'
       endif
       csize(icix)=size
       READ(fhr,*) ! Comment: Independent components are
       READ(fhr,*) (legend(i,icix),i=1,size)

       READ(fhr,*) ! Comment: Sigind follows
       do i=1,wndim
          READ(fhr,*) (Sigind(i,j,icix),j=1,wndim)
          Sigind_orig(i,:,icix) = abs(Sigind(i,:,icix))
          do j=1,wndim
             Sigind(i,j,icix)=abs(Sigind(i,j,icix))
          enddo
       enddo

       minsigind=100
       do i=1,wndim
          do j=1,wndim
             if (Sigind(i,j,icix).ne.0) then
                minsigind = min(minsigind,Sigind(i,j,icix))
             endif
             if (Sigind_orig(i,j,icix).gt.ntcix) then
                ntcix=Sigind_orig(i,j,icix)
             endif
          enddo
       enddo

       if (minsigind.ne.1) then
          do i=1,wndim
             do j=1,wndim
                if (Sigind(i,j,icix).ne.0) then
                   Sigind(i,j,icix) = Sigind(i,j,icix)-minsigind+1
                endif
             enddo
          enddo
          
          if (Qprint) then
             WRITE(fh_stdout,*) 'Sigind corrected to'
             do i=1,wndim
                do j=1,wndim
                   WRITE(fh_stdout,'(I3,1x)',advance='no') Sigind(i,j,icix)
                enddo
                WRITE(fh_stdout,*)
             enddo
          endif
       endif
       
       READ(fhr,*) ! Comment: Transformation matrix follows
       do i=1,wndim
          READ(fhr,*) (wtmpx(j),j=1,2*wndim)
          do j=1,wndim
             CF(i,j,icix) = dcmplx(wtmpx(2*j-1),wtmpx(2*j))
          enddo
       enddo

       do i=1,wndim
          if (.not.Qident) exit
          do j=1,wndim
             if (i.eq.j) then
                ident=1
             else 
                ident=0
             endif
             if (abs(CF(i,j,icix)-ident)>1e-5) then
                Qident=.False.
                exit
             endif
          enddo
       enddo

       if (Qprint) then
          write(fh_stdout,*)' Correlated block number', icix
          write(fh_stdout,*)' Correlated index='
          do m1=1,wndim
             do m2=1,wndim
                write(fh_stdout,'(I3)',advance='no') Sigind(m1,m2,icix)
             enddo
             write(fh_stdout,*)
          enddo
          write(fh_stdout,*)' Real part of unitary matrix='
          do m1=1,wndim
             do m2=1,wndim
                write(fh_stdout,'(F8.4)',advance='no') dble(cf(m1,m2,icix))
             enddo
             write(fh_stdout,*)
          enddo
          write(fh_stdout,*)' Imaginary part of unitary matrix='
          do m1=1,wndim
             do m2=1,wndim
                write(fh_stdout,'(F8.4)',advance='no') aimag(cf(m1,m2,icix))
             enddo
             write(fh_stdout,*)
          enddo
       endif
    enddo
    DEALLOCATE(wtmpx)

    if (Qprint) then
       if (Qident) then
          write(fh_stdout,*)' All transformation matrices are Identity'
       else
          write(fh_stdout,*)' At least one transformation matrix is not Identity'
       endif
    endif
120 FORMAT(' New z axis || ',3f9.4)
121 FORMAT('        Energy to separate low and high energy','states: ',f10.5)
1013 FORMAT('LOCAL ROT MATRIX:   ',3f10.7,/,20x,3f10.7,/,20x,3f10.7)
  END SUBROUTINE Read_indmfl

  SUBROUTINE DeallocateDmf()
    DEALLOCATE(nl )
    DEALLOCATE(ll, qsplit, cix, iatom)
    DEALLOCATE(crotloc)
    DEALLOCATE( isort )
    DEALLOCATE( shft )
    DEALLOCATE( CF )      ! transformation matrix
    DEALLOCATE( Sigind )  ! correlated index
    DEALLOCATE( legend )       ! names of correlated orbitals
    DEALLOCATE( csize )                 ! independent components
    DEALLOCATE( Sigind_orig )  ! correlated index                                                                                                                                                                               
  END SUBROUTINE DeallocateDmf
  
END MODULE dmfts
