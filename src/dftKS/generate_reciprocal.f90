SUBROUTINE generate_reciprocal(RKM,Sk,nat,nmatmax1,nmat_only)
!!! variables, which are set in this subroutine:
  ! KZZ        : reciprocal vectors in integer representation
  ! XK, YK, ZK : reciprocal vectors in cartesian coordinate system (of primitive unit cell)
  ! RK         : length of the reciprocal vector with coordinates (xk,yk,zk) and integer coordinates kzz
  ! RKMT       : max(RK)*min(Rmt) -- the smallest MT-radius times the largest reciprocal vector length
  ! NV         : number of reciprocal vectors (withouth local orbitals)
  ! cut        : if the allocated arrays were too small, we set this to .true.
  use matrices, only: KZZ, RK, Kn
  use lolog, only : nlo
  use structure, only: lattic, ALAT, ortho, BR2, Rmt
  use lstapw, only  : RKMT, NV
  use cut1, only  : CUT
  use nmr, only  : korig
  use param, only : nvec1, nvec2, nvec3, nume
  use lapw_timer, only : time_coor,  start_timer, stop_timer
  IMPLICIT NONE
  logical, intent(in) :: nmat_only
  INTEGER, intent(in) :: NAT, nmatmax1
  REAL*8, intent(in)  :: RKM, Sk(3)
  !..................................................................
  !   LAPW list generator for K-basis
  !..................................................................
  !   Local Scalars
  integer      :: nvec1loc,nvec2loc,nvec3loc
  INTEGER      :: IV, J, JA, JB, JC, M, N, NDM1, NV1, NV2, NV3
  REAL*8       :: DELTA, RKQ
  real*8       :: RKQ0, korig_(3) !korigx, korigy, korigz, SBX0, SBY0, SBZ0
  REAL*8       :: RNN, PI, PIA(3)
  REAL*8       :: Sk_(3), SB(3), Qt(3)
  INTEGER      :: ik(3)
  !        Data statements
  DATA DELTA /1.0D-2/
  !
  CALL START_TIMER(time_coor)
  
  PI=ACOS(-1.0D0)  
  PIA(1:3)=2.d0*PI/ALAT(1:3)
  
  IF (ORTHO) THEN
     Sk_(:)    = PIA(:)*Sk(:)
     korig_(:) = PIA(:)*korig(:)
  ELSE
     Sk_(:)    = matmul(BR2, Sk)
     korig_(:) = matmul(BR2,korig)
  ENDIF

  NVEC1loc=nvec1
  NVEC2loc=nvec2
  NVEC3loc=nvec3
  
1 CONTINUE
  
  NDM1 = NMATMAX1 + 1 - NLO
  RK(NDM1) = 1.0D+10
  N = 0
  JA = -NVEC1loc

  DO JA=-NVEC1loc+1,NVEC1loc-1
     ik(1)=ja
     DO JB=-NVEC2loc+1,NVEC2loc-1
        ik(2)=jb
        DO JC=-NVEC3loc+1,NVEC3loc-1
           ik(3)=jc
           N = N + 1
           !SB(:) = Sk_(:) + matmul(BR2,ik)
           SB(1) = Sk_(1) + BR2(1,1)*ik(1) + BR2(1,2)*ik(2) + BR2(1,3)*ik(3)
           SB(2) = Sk_(2) + BR2(2,1)*ik(1) + BR2(2,2)*ik(2) + BR2(2,3)*ik(3)
           SB(3) = Sk_(3) + BR2(3,1)*ik(1) + BR2(3,2)*ik(2) + BR2(3,3)*ik(3)
           
           RKQ = SQRT(SB(1)**2+SB(2)**2+SB(3)**2)
           RKQ0 = SQRT((SB(1)-korig(1))**2+(SB(2)-korig(2))**2+(SB(3)-korig(3))**2)
           
           IF (RKQ0 .LE. RKM) THEN
              IF (N .GT. NDM1) then
                 ! We are running out of space. Just try to put this point at the end.
                 N = NDM1
                 cut=.true.
              endif
              ! store vectors so that they are sorted according to their lebgth RKQ
              M=N-1
              DO WHILE(M.GE.1 .and. RK(M) .GT. RKQ)
                 ! Vectors should be sorted accoring to RKQ.
                 ! We shift all vectors with larger RK down the list
                 ! to make room for the current vector.
                 RK(M+1) = RK(M)
                 Kn(:,M+1) = Kn(:,M)
                 KZZ(:,M+1) = KZZ(:,M)
                 M=M-1
              ENDDO
              M = M + 1
              IF (M .GE. NDM1 .AND. RK(NDM1).LT. RKQ) THEN
                 ! If we are runnig out of space (M>NDM1) and the previous last point was further away that this one,
                 ! we remove previous last point and keep this one.
                 N=N-1
                 CYCLE
              ENDIF
              ! Now we store the new vector into M-th place
              RK(M) = RKQ
              Kn(:,M) = SB(:)
              IF (ORTHO) THEN
                 Qt(:) = SB(:)/PIA(:) - Sk(:)
                 KZZ(:,M) = int( Qt(:) + SIGN(DELTA,Qt(:)) )
              ELSE
                 KZZ(:,M) = ik(:)
                 !....transfer monocl.CXZ coord into "simple" monoclinc
                 if(lattic(1:3).eq.'CXZ') then
                    KZZ(1,M)=ik(1)+ik(3)
                    KZZ(2,M)=ik(2)
                    KZZ(3,M)=ik(3)-ik(1)
                 endif
              ENDIF
           ELSE
              N = N - 1
           ENDIF
        ENDDO
     ENDDO
  ENDDO
  
  IF (N .GE. (NMATMAX1-NLO)) THEN
     cut=.true.
     DO J = 1,NDM1
        N = NDM1 - J
        IF (ABS(RK(N)-RK(N+1)) .GT. 1.0D-5) EXIT
     ENDDO
  ENDIF
  
  !RNN = Rmt(1)
  !DO IA =2,nat
  !   IF (Rmt(IA).LT.RNN) RNN=RMT(IA)
  !ENDDO
  RNN = minval(Rmt(1:nat))
  RKMT = RK(N)*RNN
  !
  NV = N
!!!
  !write(6,*) 'calkpt: nv, nlo, nume:', nv, nlo, nume
  !write(6,*) 'size: rk,kzz: ', size(rk,1), size(kzz,1), size(kzz,2)
  !write(6,*) 'size: rk,kzz(1,2): ', size(rk,1), size(kzz,1), size(kzz,2)
  !do iv=1,nv
  !   write(6,*) kzz(1,iv),kzz(2,iv),kzz(3,iv),xk(iv),yk(iv),zk(iv)
  !enddo
!!!
  DO IV = 1, 2
     IF (IV .EQ. 1) THEN
        NV1 = -NVEC1loc
        NV2 = -NVEC2loc
        NV3 = -NVEC3loc
     ELSE
        NV1 = NVEC1loc
        NV2 = NVEC2loc
        NV3 = NVEC3loc
     ENDIF
     ik(1)=NV1
     ik(2)=0
     ik(3)=0
     DO
        !SB(:) = Sk_(:) + matmul(BR2,ik)
        SB(1) = Sk_(1) + BR2(1,1)*ik(1) + BR2(1,2)*ik(2) + BR2(1,3)*ik(3)
        SB(2) = Sk_(2) + BR2(2,1)*ik(1) + BR2(2,2)*ik(2) + BR2(2,3)*ik(3)
        SB(3) = Sk_(3) + BR2(3,1)*ik(1) + BR2(3,2)*ik(2) + BR2(3,3)*ik(3)
        
        RKQ = SQRT(SB(1)**2+SB(2)**2+SB(3)**2)
        IF (RKQ .LT. RK(NV)) THEN
           IF (ik(1) .EQ. NV1) THEN
              write(6,*) 'NVEC1 too small.',nvec1loc,ik(1),rk(nv),rkq
              nvec1loc=nvec1loc*2
           ELSEIF (ik(2) .EQ. NV2) THEN
              write(6,*) 'NVEC2 too small.',nvec2loc,ik(2),rk(nv),rkq
              nvec2loc=nvec2loc*2
           ELSE
              write(6,*) 'NVEC3 too small.',nvec3loc,ik(3),rk(nv),rkq
              nvec3loc=nvec3loc*2
           ENDIF
           goto 1
        ELSEIF (ik(2) .EQ. NV2) THEN
           ik(3)=NV3
           ik(2)=0
        ELSEIF (ik(3) .NE. NV3) THEN
           ik(2)=NV2
           ik(1)=0
        ELSE
           EXIT
        ENDIF
     ENDDO
  ENDDO
  CALL STOP_TIMER(time_coor)
  if(nmat_only) then
     write(72,*) nv+nlo
     return  !         stop 'NMAT_ONLY'
  endif
  
  RETURN
END SUBROUTINE generate_reciprocal
