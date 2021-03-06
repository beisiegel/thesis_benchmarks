!
!
!     =====================================================
      subroutine flux2(ixy,maxm,meqn,maux,mbc,mx, &
                      q1d,dtdx1d,aux1,aux2,aux3, &
                      faddm,faddp,gaddm,gaddp,cfl1d, &
                      rpn2,rpt2)
!!                      fwave,s,amdq,apdq,rpn2,rpt2)
!     =====================================================
!
!     # clawpack routine ...  modified for AMRCLAW
!
!--------------------------------------------------------------------
!     # flux2fw is a modified version of flux2 to use fwave instead of wave.
!     # A modified Riemann solver rp2n must be used in conjunction with this
!     # routine, which returns fwave's instead of wave's.
!     # See http://amath.washington.edu/~claw/fwave.html
!
!     # Limiters are applied to the fwave's, and the only significant
!     # modification of this code is in the "do 119" loop, for the
!     # second order corrections.
!
!--------------------------------------------------------------------
!
!
!     # Compute the modification to fluxes f and g that are generated by
!     # all interfaces along a 1D slice of the 2D grid.
!     #    ixy = 1  if it is a slice in x
!     #          2  if it is a slice in y
!     # This value is passed into the Riemann solvers. The flux modifications
!     # go into the arrays fadd and gadd.  The notation is written assuming
!     # we are solving along a 1D slice in the x-direction.
!
!     # fadd(i,.) modifies F to the left of cell i
!     # gadd(i,.,1) modifies G below cell i
!     # gadd(i,.,2) modifies G above cell i
!
!     # The method used is specified by method(2:3):
!
!         method(2) = 1 if only first order increment waves are to be used.
!                   = 2 if second order correction terms are to be added, with
!                       a flux limiter as specified by mthlim.
!
!         method(3) = 0 if no transverse propagation is to be applied.
!                       Increment and perhaps correction waves are propagated
!                       normal to the interface.
!                   = 1 if transverse propagation of increment waves
!                       (but not correction waves, if any) is to be applied.
!                   = 2 if transverse propagation of correction waves is also
!                       to be included.
!
!     Note that if mcapa>0 then the capa array comes into the second
!     order correction terms, and is already included in dtdx1d:
!     If ixy = 1 then
!        dtdx1d(i) = dt/dx                      if mcapa= 0
!                  = dt/(dx*aux(i,jcom,mcapa))  if mcapa = 1
!     If ixy = 2 then
!        dtdx1d(j) = dt/dy                      if mcapa = 0
!                  = dt/(dy*aux(icom,j,mcapa))  if mcapa = 1
!
!     Notation:
!        The jump in q (q1d(i,:)-q1d(i-1,:))  is split by rpn2 into
!            amdq =  the left-going flux difference  A^- Delta q
!            apdq = the right-going flux difference  A^+ Delta q
!        Each of these is split by rpt2 into
!            bmasdq = the down-going transverse flux difference B^- A^* Delta q
!            bpasdq =   the up-going transverse flux difference B^+ A^* Delta q
!        where A^* represents either A^- or A^+.
!

!      #  modifications for GeoClaw

!--------------------------flux2fw_geo.f--------------------------
!     This version of flux2fw.f is modified slightly to be used with
!     step2_geo.f  The only modification is for the first-order
!     mass fluxes, faddm(i,j,1) and faddp(i,j,1), so that those terms are true
!     interface fluxes.
!
!     The only change is in loop 40
!     to revert to the original version, set relimit = .false.
!---------------------last modified 1/04/05-----------------------------

      use amr_module, only: use_fwaves, mwaves, method
      use amr_module, only: mthlim
      use geoclaw_module, only: coordinate_system, earth_radius, deg2rad
#ifdef USEPAPI
      use papi_module
#endif

      implicit double precision (a-h,o-z)

      external rpn2, rpt2

      !dimension  q1d_aos(meqn, 1-mbc:maxm+mbc)
      dimension  q1d(1-mbc:maxm+mbc,meqn)

      dimension  bmasdq(meqn, 1-mbc:maxm+mbc)
      dimension  bpasdq(meqn, 1-mbc:maxm+mbc)
      dimension  cqxx(meqn, 1-mbc:maxm+mbc)
      dimension  faddm(meqn,1-mbc:maxm+mbc)
      dimension  faddp(meqn,1-mbc:maxm+mbc)
      dimension  gaddm(meqn,1-mbc:maxm+mbc, 2)
      dimension  gaddp(meqn,1-mbc:maxm+mbc, 2)
      dimension  dtdx1d(1-mbc:maxm+mbc)
      dimension  aux1(1-mbc:maxm+mbc,maux)
      dimension  aux2(1-mbc:maxm+mbc,maux)
      dimension  aux3(1-mbc:maxm+mbc,maux)
!
      dimension  s(mwaves,1-mbc:maxm+mbc)
      dimension  fwave(meqn, mwaves, 1-mbc:maxm+mbc)
      dimension  amdq(meqn, 1-mbc:maxm+mbc)
      dimension  apdq(meqn, 1-mbc:maxm+mbc)
!
      logical limit, relimit
!!!!!!SOA!!!!!
!      do i=1-mbc,maxm+mbc
!          q1d(i,:) = q1d_aos(:,i)
!      enddo
!!!!!!SOA!!!!!


      relimit = .false.
!
      limit = .false.
      do 5 mw=1,mwaves
         if (mthlim(mw) .gt. 0) limit = .true.
   5     continue
!
!     # initialize flux increments:
!     -----------------------------
!

      do 30 jside=1,2
        do 20 i = 1-mbc, mx+mbc
          do 10 m=1,meqn
               faddm(m,i) = 0.d0
               faddp(m,i) = 0.d0
               gaddm(m,i,jside) = 0.d0
               gaddp(m,i,jside) = 0.d0
   10          continue
   20       continue
   30    continue

!
!
!     # solve Riemann problem at each interface and compute Godunov updates
!     ---------------------------------------------------------------------
!
      call rpn2(ixy,maxm,meqn,mwaves,maux,mbc,mx,q1d,q1d, &
               aux2,aux2,fwave,s,amdq,apdq)

!
!   # Set fadd for the donor-cell upwind method (Godunov)
      if (ixy.eq.1) mu=2
      if (ixy.eq.2) mu=3
      do 40 i=1-mbc+1,mx+mbc-1
         if (coordinate_system.eq.2) then
              if (ixy.eq.1) then
                   dxdc=earth_radius*deg2rad
              else  
                  dxdc=earth_radius*cos(aux2(i,3))*deg2rad
!                  if (ixy.eq.2) dxdc=earth_radius*cos(aux2(3,i))*deg2rad  !why test again
              endif
         else
            dxdc=1.d0
         endif

          do m=1,meqn
            faddp(m,i) = faddp(m,i) - apdq(m,i)
            faddm(m,i) = faddm(m,i) + amdq(m,i)
          enddo
          if (relimit) then
            !faddp(1,i) = faddp(1,i) + dxdc*q1d_aos(mu,i)
            faddp(1,i) = faddp(1,i) + dxdc*q1d(i,mu)
            faddm(1,i) = faddp(1,i)
          endif
   40       continue
!
!     # compute maximum wave speed for checking Courant number:
      cfl1d = 0.d0
      do 50 mw=1,mwaves
         do 50 i=1,mx+1
!          # if s>0 use dtdx1d(i) to compute CFL,
!          # if s<0 use dtdx1d(i-1) to compute CFL:
            cfl1d = dmax1(cfl1d, dtdx1d(i)*s(mw,i), &
                               -dtdx1d(i-1)*s(mw,i))

   50       continue
!
      if (method(2).eq.1) go to 130
!
!     # modify F fluxes for second order q_{xx} correction terms:
!     -----------------------------------------------------------
!
!     # apply limiter to fwaves:
      if (limit) call limiter(maxm,meqn,mwaves,mbc,mx,fwave,s,mthlim)
!
      do 120 i = 1, mx+1
!
!        # For correction terms below, need average of dtdx in cell
!        # i-1 and i.  Compute these and overwrite dtdx1d:
!
         dtdx1d(i-1) = 0.5d0 * (dtdx1d(i-1) + dtdx1d(i))
!
         do 120 m=1,meqn
            cqxx(m,i) = 0.d0
            do 119 mw=1,mwaves
!
!              # second order corrections:
               cqxx(m,i) = cqxx(m,i) + dsign(1.d0,s(mw,i)) &
                 * (1.d0 - dabs(s(mw,i))*dtdx1d(i-1)) * fwave(m,mw,i)
!
  119          continue
            faddm(m,i) = faddm(m,i) + 0.5d0 * cqxx(m,i)
            faddp(m,i) = faddp(m,i) + 0.5d0 * cqxx(m,i)
  120       continue
!
!
  130  continue
!
       if (method(3).eq.0) go to 999   !# no transverse propagation
!
       if (method(2).gt.1 .and. method(3).eq.2) then
!         # incorporate cqxx into amdq and apdq so that it is split also.
          do 150 i = 1, mx+1
             do 150 m=1,meqn
                amdq(m,i) = amdq(m,i) + cqxx(m,i)
                apdq(m,i) = apdq(m,i) - cqxx(m,i)
  150           continue
          endif
!
!
!      # modify G fluxes for transverse propagation
!      --------------------------------------------
!
!
!     # split the left-going flux difference into down-going and up-going:
#ifdef USEPAPI
      call papi_start()
#endif
      call rpt2(ixy,1,maxm,meqn,mwaves,maux,mbc,mx, &
               q1d,q1d,aux1,aux2,aux3, &
               amdq,bmasdq,bpasdq)
#ifdef USEPAPI
      call papi_stop(mx)
#endif
!
!     # modify flux below and above by B^- A^- Delta q and  B^+ A^- Delta q:
      do 160 i = 1, mx+1
         do 160 m=1,meqn
               gupdate = 0.5d0*dtdx1d(i-1) * bmasdq(m,i)
               gaddm(m,i-1,1) = gaddm(m,i-1,1) - gupdate
               gaddp(m,i-1,1) = gaddp(m,i-1,1) - gupdate
!
               gupdate = 0.5d0*dtdx1d(i-1) * bpasdq(m,i)
               gaddm(m,i-1,2) = gaddm(m,i-1,2) - gupdate
               gaddp(m,i-1,2) = gaddp(m,i-1,2) - gupdate
  160          continue
!
!     # split the right-going flux difference into down-going and up-going:
#ifdef USEPAPI
      call papi_start()
#endif
      call rpt2(ixy,2,maxm,meqn,mwaves,maux,mbc,mx, &
               q1d,q1d,aux1,aux2,aux3, &
               apdq,bmasdq,bpasdq)
#ifdef USEPAPI
      call papi_stop(mx)
#endif
!
!     # modify flux below and above by B^- A^+ Delta q and  B^+ A^+ Delta q:
      do 180 i = 1, mx+1
          do 180 m=1,meqn
               gupdate = 0.5d0*dtdx1d(i-1) * bmasdq(m,i)
               gaddm(m,i,1) = gaddm(m,i,1) - gupdate
               gaddp(m,i,1) = gaddp(m,i,1) - gupdate
!
               gupdate = 0.5d0*dtdx1d(i-1) * bpasdq(m,i)
               gaddm(m,i,2) = gaddm(m,i,2) - gupdate
               gaddp(m,i,2) = gaddp(m,i,2) - gupdate
  180          continue
!
  999 continue
      return
      end
