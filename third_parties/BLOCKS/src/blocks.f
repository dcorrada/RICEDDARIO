      Program blocks
       implicit double precision (a-h,o-z)
       parameter (liv = 500000000)
       dimension iv(liv)
       logical total,final,active,flag3
       namelist/params/nres,fract,total,ntm,percomp,ngrain,length
C
C  INPUT PARAMETERS: - Total number of eigenvectors (nres);
C                    - Threshold for considering the eigenvectors (e.g., fract=0.6 means that we "accept" 
C                      eigenvectors whose eigenvalue is, in absolute value, greater than or equal to
C                      0.6*abs(eigval(1)) where eigval(1) is the lowest eigenvalue); 
C                    - Logical variable to indicate if considering NRES (total=.true.) eigenvectors or only
C                      NAM eigenvectors (logical=.false.) in the computation of the median for the binary 
C                      discretization;
C                    - Maximum number of times that a component can be covered (ntm)
C                    - Maximum fraction of the total number of components that can be covered ntm times (percomp);
C                    - Side-length of the starting diagonal tesserae (ngrain);
C                    - Minimal domain dimension (length).
C
       read(5,params)
       idbl=2
       final=.true.
       nb=10
       ntr=nres*(nres+1)/2
C
C Determining the number of diagonal tesserae
C
       call diagtes(nres,ngrain,ndiag)
C
       i1  =   1 
       i2  =  i1 + nres*nres*idbl                !evec(nres,nres)
       i3  =  i2 + nres*idbl                     !eigval(nres)
C
C Reading the eigenvectors and the eigenvalues
C
       call leggi_evec(iv(i1),iv(i2),nres)
C
C Determining the number of eigenvectors to be considered (NAM)        
C
       call findevec(iv(i2),nres,fract,nam)
C
C Printing the considered eigenvectors (absolute value of the components)
C
       call print_evec(iv(i1),nres,nam)
C
       if (total) then
         i4  =  i3 + nres*nres*idbl              !ovec(nres*nres)
       else
         i4  =  i3 + nam*nres*idbl               !ovec(nam*nres)
       end if
C
       i5  =  i4 + nres*nres                     !ivec(nres,nres)
       i6  =  i5 + nam*idbl                      !pjoint(nam)
       i7  =  i6 + nam+1                         !matclust(0:nam)
       i8  =  i7 + ntr                           !kp(ntr)
       i9  =  i8 + nam                           !ichk(nam)
      i10  =  i9 + nres                          !ichk2(nres)
      i11  = i10 + ntr*idbl                      !energy(ntr)
      i12  = i11 + nb                            !ifreq(nb)
      i13  = i12 + (nb+1)*idbl                   !cpoint(nb+1)
      i14  = i13 + nres+1                        !missing(0:nres)
      i15  = i14 + ntr*idbl                      !ordene(ntr)
      i16  = i15 + ntr*idbl                      !benergy(ntr)
      i17  = i16 + ndiag*(nres+1)                !ktes(ndiag,0:nres)
      i18  = i17 + ndiag*idbl                    !dens(ndiag)
      i19  = i18 + ndiag*(nres+1)                !isl(ndiag,0:nres)
      i20  = i19 + nres                          !ichk2_old(nres)
C
C Ordering the components for the median calculation
C
       if (total) then
         call order1(iv(i1),iv(i3),nres,thr)                            !All the NRES eigenvectors are considered
       else
         call order2(iv(i1),iv(i3),nres,nam,thr)                        !Only NAM eigenevctors are considered
       end if
C
C Symbolizing the eigenvectors components
C
       call symbolize(iv(i1),iv(i4),nres,thr)
C
C Creating the vector kp
C
       call ivett(iv(i7),ntr)
C
C Determining the essential cluster of eigenvectors
C
       call essential(iv(i4),iv(i5),iv(i6),iv(i8),iv(i9),iv(i13),
     &                iv(i19),nres,nam,ntr,ntm,percomp)
C
C Reconstructing the energy interaction matrix
C
       call rec_ene(iv(i1),iv(i2),iv(i6),iv(i7),iv(i10),iv(i11),iv(i12),
     &              nres,nam,ntr,nb)
C
C Blocking the reconstructed Interaction Energy Matrix
C
       call blocking(iv(i2),iv(i7),iv(i10),iv(i15),nres,ntr,denstot)
C
C Constructing the starting diagonal tesserae
C
       call buildtes(iv(i16),ndiag,nres,ngrain)
C
C Computing the "Density" of the starting diagonal tesserae
C
       call diagdens(iv(i7),iv(i15),iv(i16),iv(i17),ntr,ntr,ndiag,nres)
C
C Clusterizing consecutive starting diagonal tesserea (when it is possible) 
C
       nclust=0
       call cluster1(iv(i7),iv(i15),iv(i16),iv(i17),iv(i18),ntr,ntr,
     &               ndiag,nres,denstot,nclust)
C
C (Re)Allocating memory 
C
       ntr2=nclust*(nclust+1)/2
       i20  = i19 + ntr2*idbl                    !dbim(ntr2)
       i21  = i20 + nclust                       !list(nclust) 
C
       call dinitialize(iv(i19),ntr2)
C
C Further clusterizations of the obtained blocks (until convergence)
C
       call cluster_conv(iv(i7),iv(i15),iv(i18),iv(i19),iv(i20),ntr,ntr,
     &                   ndiag,nres,ntr2,nclust,denstot)
C
C Checking if the domains satisfy the minimal length requirement
C 
       call minimal(iv(i18),iv(i20),ndiag,nres,nclust,nct,length)
C
C Allocating memory
C
       i22  = i21 + nct*(nres+1)                 !idom(nct,0:nres)
       i23  = i22 + nct*(nres+1)                 !intv(nct,0:nres)
C
       call initialize(iv(i21),nct*(nres+1))
       call initialize(iv(i22),nct*(nres+1))
C
C Copying the domains residue indexes in idom (isl ----> idom)
C
       call copy_dom(iv(i18),iv(i20),iv(i21),ndiag,nres,nclust,nct)
C
C Ordering the residue indexes in idom
C
       call order_dom(iv(i21),nct,nres)
C
C Filling the gaps in the domains
C
       call turkey(iv(i18),iv(i20),iv(i21),ndiag,nres,nclust,nct)
C
C Ordering again the residue indexes in idom
C
       call order_dom(iv(i21),nct,nres)
C
C Writing the domains in a more compact way
C
       write(6,*)
       write(6,*) 'FIRST CLUSTERING..........'
       call compact(iv(i21),iv(i22),nct,nres,nct)
C
       if (nct .gt. 1) then
         nctmax=50*nct                                                 
         minl=2*length                                                  !Minimal length for further analysis
         nctprv=nct                                                     !Current number of domains
         nstep=0
         final=.false.
C
C Allocating memory
C
         i24  = i23 + nctmax                     !iact(nctmax)
C
C Constructing the iact array
C
         call build_iact(iv(i21),iv(i23),nct,nres,nctmax,minl)
C
C Summing the elements of the iact array
C
         call sum_iact(iv(i23),nctmax,nctprv,jsm)
C
C Allocating memory
C
         i25  = i24 + nctmax*(nres+1)          !newdom(nctmax,0:nres)
         i26  = i25 + nctmax*(nres+1)          !intv2(nctmax,0:nres)
C
C Copying idom into newidom
C
         call initialize(iv(i24),nctmax*(nres+1))
         call initialize(iv(i25),nctmax*(nres+1))
         call copy_idom(iv(i21),iv(i24),nct,nres,nctmax)
C
         if (jsm .ne. 0) then
C
C Allocating memory
C
 500       i27  = i26 + nctprv                   !kpoint(nctprv)           
C
           call initialize(iv(i26),nctprv)
           nstep=nstep+1
C
C Constructing the starting kpoint array
C
           call build_kpnt(iv(i26),nctprv)
C
           isum=0
           nprov=nctprv
           do nn=1,nctprv
             active=.false.
             call recindx(iv(i23),iv(i26),nctmax,nctprv,nn,jpt,active) !Assigning the values to jpt and active
             if (active) then
               call recdim(iv(i24),nctmax,nres,jpt,ndim)               !Recovering the dimensions of the domain in exam
               call diagtes(ndim,ngrain,ndg)                           !Computing the number of diagonal tesserae
               ntr3=ndim*(ndim+1)/2
C
C Allocating memory
C
               i28  = i27 + ntr3*idbl            !bmini(ntr3)
               i29  = i28 + ndg*(ndim+1)         !ktes2(ndg,0:ndim)
               i30  = i29 + ndg*idbl             !dens2(ndg)
               i31  = i30 + ndg*(ndim+1)         !isl2(ndg,0:ndim)
C
C Initializing the arrays and the matrices
C
               call dinitialize(iv(i27),ntr3)
               call initialize(iv(i28),ndg*(ndim+1))
               call dinitialize(iv(i29),ndg)
               call initialize(iv(i30),ndg*(ndim+1))
C
C Extracting bmini from benergy
C
               call extract_bmini(iv(i7),iv(i15),iv(i24),iv(i27),ntr,
     &                            nctmax,nres,ntr3,jpt,ndim,dt2)
C
C Constructing the starting diagonal tesserae
C
               call buildtes(iv(i28),ndg,ndim,ngrain)
C
C Computing the "Density" of the starting diagonal tesserae
C
               call diagdens(iv(i7),iv(i27),iv(i28),iv(i29),ntr,ntr3,
     &                       ndg,ndim)
C
C Clusterizing consecutive starting diagonal tesserea (when it is possible) 
C
               nclust2=0
               call cluster1(iv(i7),iv(i27),iv(i28),iv(i29),iv(i30),ntr,
     &                       ntr3,ndg,ndim,dt2,nclust2)
C
C Allocating memory 
C
               ntr4=nclust2*(nclust2+1)/2
               i32  = i31 + ntr4*idbl            !dbim2(ntr4)
               i33  = i32 + nclust2              !list2(nclust2) 
C
C Further clusterizations of the obtained blocks (until convergence)
C
               call cluster_conv(iv(i7),iv(i27),iv(i30),iv(i31),iv(i32),
     &                           ntr,ntr3,ndg,ndim,ntr4,nclust2,dt2)
C
C Checking if the domains satisfy the minimal length requirement
C 
               call minimal(iv(i30),iv(i32),ndg,ndim,nclust2,nct2,
     &                      length)
C
C Allocating memory
C
               i34  = i33 + nct2*(ndim+1)        !idom2(nct2,0:ndim)
C
               call initialize(iv(i33),nct2*(ndim+1)) 
C
C Copying the domains residue indexes in idom2 (isl2 ----> idom2)
C
               call copy_dom(iv(i30),iv(i32),iv(i33),ndg,ndim,nclust2,
     &                       nct2)
C
C Ordering the residue indexes in idom2
C
               call order_dom(iv(i33),nct2,ndim2)
C
C Filling the gaps in the domains
C
               call turkey(iv(i30),iv(i32),iv(i33),ndg,ndim,nclust2,
     &                     nct2)
C
C Ordering again the residue indexes in idom
C
               call order_dom(iv(i33),nct2,ndim2)
C
C Updating fundamental arrays: iaction, newdom and kpoint 
C
               if (nct2 .lt. 2) then
                 call updating1(iv(i23),nctmax,jpt)
               else
                 i35  = i34 + nres               !nnap(nres)              
                 call initialize(iv(i34),nres)                          !Initializing nnap
                 call copy2nnap(iv(i24),iv(i34),nctmax,nres,jpt)        !Copying the jpt-th row of newdom into nnap
                 call updating2(iv(i23),iv(i24),iv(i26),iv(i33),iv(i34),!Updating fundamental arrays: iact, newdom and kpoint 
     &                          nctmax,nres,nctprv,nct2,ndim,nn,minl,
     &                          nprov)
                 isum=isum+nct2-1
                 nprov=nprov+isum
               end if
             end if          
           end do
           nctprv=nctprv+isum
C
C Writing the domains in a more compact way
C
           write(6,*)
           write(6,*)
           write(6,*) 'AFTER FURTHER CLUSTERING..........'
           call compact(iv(i24),iv(i25),nctmax,nres,nctprv)
C
C Summing the elements of the iact array
C
           call sum_iact(iv(i23),nctmax,nctprv,jsm)
           if (jsm .ne. 0) goto 500                                     !Exit condition
         end if
       end if
C
C Writing the domains in a more compact way
C
       if (final) then
         write(6,*)
         write(6,*)
         write(6,*) 'FINAL DOMAINS: '
         call compact(iv(i21),iv(i22),nct,nres,nct)
       else
         write(6,*)
         write(6,*)
         write(6,*) 'AFTER FURTHER CLUSTERING..........'
         call compact(iv(i24),iv(i25),nctmax,nres,nctprv)
C
C (Re)Allocating memory
C
         i27  = i26 + nres*nres                  !matcont(nres,nres)
         i28  = i27 + nctmax*2                   !indx(nctmax,2)
         i29  = i28 + nctprv*(nres+1)            !islapp(nctprv,0:nres)
         i30  = i29 + nctprv                     !list(nctprv)
C
C Reading the contacts matrix
C
         call initialize(iv(i26),nres*nres)
         call readcontact(iv(i26),nres)
C
C Determining the small clusters in the domains
C
 222     call initialize(iv(i27),nctmax*2) 
         call smallclust(iv(i25),iv(i27),nctmax,nres,nctmax,nctprv,
     &                   length,nsmall)
C
         if (nsmall .ne. 0) then
           write(6,*)
           write(6,*)           
           write(6,*) 'CONTACTS MATRIX REFINEMENT..........'
C
           do k=1,nsmall
C
C Determining the domain where to move the small cluster
c
             call denscont(iv(i25),iv(i26),iv(i27),nctmax,nres,nctprv,k,
     &                     kdom,length,move)
C
             if (move .ne. kdom) then
               call change(iv(i25),iv(i27),nctmax,nres,k,move)          !Moving the small cluster to the selected domain (kdom ---> move)
               call minreq(iv(i25),nctmax,nres,nctprv,length)           !Checking the minimum length requirement of the domains
               call initialize(iv(i28),nctprv*(nres+1))
               call initialize(iv(i29),nctprv)
               call creating(iv(i25),iv(i28),iv(i29),nctmax,nres,nctprv,!Creating islapp and list from intv2
     &                       ndnew)
               call initialize(iv(i24),nctmax*(nres+1))
               call copy_dom(iv(i28),iv(i29),iv(i24),nctprv,nres,nctprv,!Copying islapp into newdom (islapp ---> newdom)
     &                       nctmax)
               call order_dom(iv(i24),nctmax,nres)                      !Ordering newdom
               call turkey(iv(i28),iv(i29),iv(i24),nctprv,nres,nctprv,  !Filling the gaps in newdom
     &                     nctmax) 
               call order_dom(iv(i24),nctmax,nres)                      !Ordering newdom
               nctprv=ndnew
               call initialize(iv(i25),nctmax*(nres+1)) 
               call compact(iv(i24),iv(i25),nctmax,nres,nctprv)         !Writing the domains in a more comapct way
               goto 222
             end if
           end do
           write(6,*)
           write(6,*) 'END OF CONTACTS MATRIX REFINEMENT..........'
           call initialize(iv(i25),nctmax*(nres+1))
           call compact(iv(i24),iv(i25),nctmax,nres,nctprv)
         else
           write(6,*)
           write(6,*)
           write(6,*) 'END OF CONTACTS MATRIX REFINEMENT..........'
           call initialize(iv(i25),nctmax*(nres+1))
           call compact(iv(i24),iv(i25),nctmax,nres,nctprv)
         end if
C
C Deleting the 5-residue clusters in the domains (if they constitute
C less the 10% of the domain in exam)
C
         write(6,*)
         write(6,*)
         write(6,*) 'DELETING THE "PROPER" NGRAIN-RESIDUE CLUSTERS.....'
         call fiveres(iv(i25),nctmax,nres,ngrain,nctprv)
C
         call initialize(iv(i28),nctprv*(nres+1))
         call initialize(iv(i29),nctprv)
         call creating(iv(i25),iv(i28),iv(i29),nctmax,nres,nctprv,ndnew)!Creating islapp and list from intv2
         call initialize(iv(i24),nctmax*(nres+1))
         call copy_dom(iv(i28),iv(i29),iv(i24),nctprv,nres,nctprv,      !Copying islapp into newdom (islapp ---> newdom)
     &                 nctmax)
         call order_dom(iv(i24),nctmax,nres)                            !Ordering newdom
         call turkey(iv(i28),iv(i29),iv(i24),nctprv,nres,nctprv,nctmax) !Filling the gaps in newdom
         call order_dom(iv(i24),nctmax,nres)                            !Ordering newdom
         call initialize(iv(i25),nctmax*(nres+1))
         write(6,*)
         write(6,*)
         write(6,*) 'FINAL DOMAINS:'
         call compact(iv(i24),iv(i25),nctmax,nres,nctprv)               !Writing the domains in a more comapct way
       end if
       stop
      end



C
C Subroutine to determine the number of diagonal tesserae
C
      Subroutine diagtes(nres,ngrain,ndiag)
       implicit double precision (a-h,o-z)
C
       ndiag=nres/ngrain
       bar=(nres*1.0d0)/ngrain
       val=bar-ndiag
       if (val .ge. 0.6d0) then
         ndiag=ndiag+1
       end if
       return
      end     

C
C Subroutine to read the eigenvectors and the eigenvalues 
C
      Subroutine leggi_evec(evec,eigval,nres)
       implicit double precision (a-h,o-z)
       dimension evec(nres,nres),eigval(nres)
C
       do i=1,nres
         read(30,*) (evec(i,j),j=1,nres)
       end do
C
       do i=1,nres
         read(31,*) eigval(i)
       end do
      end

C
C Subroutine to select the eigenvectors to consider
C
      Subroutine findevec(eigval,nres,fract,nam)
       implicit double precision (a-h,o-z)
       dimension eigval(nres)
C
       sgl=fract*eigval(1)
       do j=1,nres
         if (eigval(j) .gt. sgl) then
           nam=j-1
           goto 344 
         end if
       end do
 344   continue
       write(6,*) 'NUMBER OF SELECTED EIGENVECTORS: ',nam
       write(6,*)
       return
      end

C
C Subroutine to print the selected eigenvectors
C     (absolute value of the components)
C
      Subroutine print_evec(evec,nres,nam)
       implicit double precision (a-h,o-z)
       dimension evec(nres,nres)
C
       do j=1,nam
         do i=1,nres
           write(32,*) i,abs(evec(i,j))
         end do
         write(32,*)
       end do
       return
      end


   
C
C Subroutine to order the components of all the NRES eigenvectors for
C the median calculation
C
      Subroutine order1(evec,ovec,nres,thr)
       implicit double precision (a-h,o-z)
       dimension evec(nres,nres),ovec(nres*nres)
C
       icont=0
       do j=1,nres
         do i=1,nres
           icont=icont+1
           ovec(icont)=abs(evec(i,j))
         end do
       end do
C
       do i=1,nres*nres-1
         do j=i+1,nres*nres
           if (ovec(j) .lt. ovec(i)) then
             app=ovec(j)
             ovec(j)=ovec(i)
             ovec(i)=app
           end if
         end do
       end do
C
       it=int((nres*nres)/2)
C
       do i=it+1,nres*nres
         if (ovec(i) .gt. ovec(it)) then
           new_dx=i-1
           goto 333
         end if
       end do         
 333   continue
       p0=(new_dx*1.0d0)/(nres*nres)
       p1=(nres*nres-new_dx)*1.0d0/(nres*nres)
       Hdx=-1.0d0*p0*log10(p0)/log10(2.0d0)-p1*log10(p1)/log10(2.0d0)
C
       do i=it-1,1,-1
         if (ovec(i) .lt. ovec(it)) then
           new_sx=i
           goto 334
         end if
       end do 
 334   continue
       p0=(new_sx*1.0d0)/(nres*nres)
       p1=(nres*nres-new_sx)*1.0d0/(nres*nres)
       Hsx=-1.0d0*p0*log10(p0)/log10(2.0d0)-p1*log10(p1)/log10(2.0d0)
C
       if (Hdx .ge. Hsx) then
         it=new_dx
         thr=ovec(it)
       else
         it=new_sx
         thr=ovec(it)
       end if               
       write(6,*) 'MEDIAN FOR SYMBOLIZATION: ',thr
       write(6,*)
       return
      end
C
C Subroutine to order the components of only NAM eigenvectors for
C the median calculation
C
      Subroutine order2(evec,ovec,nres,nam,thr)
       implicit double precision (a-h,o-z)
       dimension evec(nres,nres),ovec(nam*nres)
C
       icont=0
       do j=1,nam
         do i=1,nres
           icont=icont+1
           ovec(icont)=abs(evec(i,j))
         end do
       end do
C
       do i=1,nam*nres-1
         do j=i+1,nam*nres
           if (ovec(j) .lt. ovec(i)) then
             app=ovec(j)
             ovec(j)=ovec(i)
             ovec(i)=app
           end if
         end do
       end do
C
       it=int((nam*nres)/2)
C
       do i=it+1,nam*nres
         if (ovec(i) .gt. ovec(it)) then
           new_dx=i-1
           goto 335
         end if
       end do 
 335   continue
       p0=(new_dx*1.0d0)/(nam*nres)
       p1=(nam*nres-new_dx)*1.0d0/(nam*nres)
       Hdx=-1.0d0*p0*log10(p0)/log10(2.0d0)-p1*log10(p1)/log10(2.0d0)
C
       do i=it-1,1,-1
         if (ovec(i) .lt. ovec(it)) then
           new_sx=i
           goto 336
         end if
       end do
 336   continue
       p0=(new_sx*1.0d0)/(nam*nres)
       p1=(nam*nres-new_sx)*1.0d0/(nam*nres)
       Hsx=-1.0d0*p0*log10(p0)/log10(2.0d0)-p1*log10(p1)/log10(2.0d0)
C
       if (Hdx .ge. Hsx) then
         it=new_dx
         thr=ovec(it)
       else
         it=new_sx
         thr=ovec(it)
       end if
       write(6,*) 'MEDIAN FOR SYMBOLIZATION: ',thr
       write(6,*)
       return 
      end

C
C Subroutine to symbolize the eigenvectors components
C             
      Subroutine symbolize(evec,ivec,nres,thr)
       implicit double precision (a-h,o-z)
       dimension evec(nres,nres),ivec(nres,nres)
C
        do i=1,nres
          do j=1,nres
            if (abs(evec(i,j)) .gt. thr) then
              ivec(i,j)=1
            else
              ivec(i,j)=0
            end if
          end do
        end do    
       return
      end
            
C
C Subroutine to determne the essential cluster of eigenvectors
C
      Subroutine essential(ivec,pjoint,matclust,ichk,ichk2,missing,
     &                     ichk2_old,nres,nam,ntr,ntm,percomp)
       implicit double precision (a-h,o-z)
       dimension ivec(nres,nres),pjoint(nam),matclust(0:nam),kp(ntr),
     &           ichk(nam),ichk2(nres),missing(0:nres),ichk2_old(nres)
       logical   flag1,flag2
C
       flag1=.false.
       flag2=.false.
       call initialize(matclust,nam+1)
       call initialize(ichk,nam)
       call initialize(ichk2,nres)
       call initialize(ichk2_old,nres)
       matclust(1)=1
       matclust(0)=matclust(0)+1
       ichk(1)=1
       ilast=1
       cont=0.0d0
C
       write(6,*)
       write(6,*) 'JUST SELECTED EIGENVECTOR: ',ilast
C
C Computing the fraction of components covered by the currently 
C selected eigenvectors
C
       call compfrac(ivec,ichk2,nres,ilast,cont,realp)
C
C Computing the redundancy associated with the set of selected 
C eigenvectors
C 
       call compred(ivec,matclust,nres,nam,ntm,percomp,redind,flag2)
       write(6,*)
C
       if (flag2) goto 337
C
C Computing the joint probabilities 
C
       jjcont=1
 338   jjcont=jjcont+1
C
       write(6,*)
       write(6,*) 'ANALYZING EIGENVECTOR ',jjcont,' OF ',nam
       write(6,*)
C
       call dinitialize(pjoint,nam)
       call compute_pj(ivec,pjoint,matclust,ichk,nres,nam)
C
C Selecting the new eigenvector of the essential cluster 
C
       call selection(ivec,pjoint,matclust,ichk,ichk2,ichk2_old,nres,
     &                nam,ilast,cont,realp,realp_old,ntm,percomp,redind,
     &                flag1,flag2)
C
       if (flag1) then
         write(6,*) 'EIGENVECTOR ',ilast,'.......... OK'
         write(6,*)
         write(6,*)
       end if
C
       if ((flag2) .or. (jjcont .eq. nam)) then
         if (jjcont .eq. nam) then
           write(6,*) 'PAY ATTENTION: REDUNDANCY LIMIT WAS NOT REACHED!'
           write(6,*)
           write(6,*)
         end if
         goto 337
       else
         goto 338
       end if
 337   continue
C
C Constructing the array of the non-covered components
C
       call noncovered(ichk2,missing,nres)
C
       knum=matclust(0)
       write(6,*) 'NUMBER OF SELECTED EIGENVECTORS: ',knum
       write(6,*)
       write(6,*) 'ESSENTIAL CLUSTER OF EIGENVECTORS: ',
     &             (matclust(i),i=1,knum)
       write(6,*)
C
       knum=missing(0)
       write(6,*) 'NUMBER OF UNCOVERED COMPONENTS: ',knum
       write(6,*) 'UNCOVERED COMPONENTS: ',(missing(i),i=1,knum)
       write(6,*)
       return
      end

C
C Subroutine to compute the fraction of components covered by the
C selected eigenvectors
C
      Subroutine compfrac(ivec,ichk2,nres,ilast,cont,realp)
       implicit double precision (a-h,o-z)
       dimension ivec(nres,nres),ichk2(nres)
C
       do i=1,nres
         if ((ivec(i,ilast) .eq. 1) .and. (ichk2(i) .eq. 0)) then
           cont=cont+1.0d0
           ichk2(i)=1
         end if
       end do
       realp=cont/nres
       write(6,*) 'FRACTION OF COVERED COMPONENTS: ',realp
       return
      end

C
C Subroutine to compute the redundancy index associated with 
C the set of selected eigenvectors
C
      Subroutine compred(ivec,matclust,nres,nam,ntm,percomp,redind,
     &                   flag2)
       implicit double precision (a-h,o-z)
       dimension ivec(nres,nres),matclust(0:nam)
       logical   flag2
C
       ired=0
       num=matclust(0)
C
       do i=1,nres
         iicont=0
         do j=1,num
           jr=matclust(j)
           if (ivec(i,jr) .eq. 1) then
             iicont=iicont+1
           end if
         end do
C 
         if (iicont .ge. ntm) then
           ired=ired+1
         end if
       end do
C
       redind=(ired*1.0d0)/nres
C
       write(6,*) 'REDUNDANCY INDEX: ',redind
       write(6,*) 'THRESHOLD       : ',percomp
C
       if (redind .gt. percomp) then 
         flag2=.true.
       end if
       return
      end            

C
C Subroutine to compute the joint probabilities
C
      Subroutine compute_pj(ivec,pjoint,matclust,ichk,nres,nam)
       implicit double precision (a-h,o-z)
       dimension ivec(nres,nres),pjoint(nam),matclust(0:nam),ichk(nam)
C
       do i=1,nam
         if (ichk(i) .eq. 0) then
           ncont=0
           do k=1,nres
             iconf=0
             do j=1,matclust(0)
               inum=matclust(j)
               if ((iconf .eq. 0) .and. (ivec(k,inum) .eq. 1)) then
                 iconf=1
                 if (ivec(k,i) .eq. 1) then
                   ncont=ncont+1
                 end if
               end if
             end do    
           end do
           pjoint(i)=(ncont*1.0d0)/nres
         else 
           pjoint(i)=2.0d0
         end if
       end do
       return
      end

C
C Subroutine to select the new eigenvector of the essential cluster
C
      Subroutine selection(ivec,pjoint,matclust,ichk,ichk2,ichk2_old,
     &                     nres,nam,ilast,cont,realp,realp_old,ntm,
     &                     percomp,redind,flag1,flag2)
       implicit double precision (a-h,o-z)
       dimension ivec(nres,nres),pjoint(nam),matclust(0:nam),ichk(nam),
     &           ichk2(nres),ichk2_old(nres)
       logical   flag1,flag2
C     
       flag1=.false.
       flag2=.false. 
       jj=matclust(0)
       vmin=10000.0d0
       imin=0
       do i=1,nam
         if ((ichk(i) .eq. 0) .and. (pjoint(i) .lt. vmin)) then
           vmin=pjoint(i)
           imin=i
         end if
       end do
C
       if (imin .ne. 0) then
         ichk(imin)=1
C
         realp_old=realp
         cont_old=cont
         call copy_ichk2s(ichk2,ichk2_old,nres)
C
         write(6,*) 'ANALYZED EIGENVECTOR: ',imin
         write(6,*)
         call compfrac(ivec,ichk2,nres,imin,cont,realp)
C
         vdif=abs(realp-realp_old)
         write(6,*) '"GAINED" INFORMATION: ',vdif
C
         if (vdif .ge. 0.01d0) then
           write(6,*)
           write(6,*) '.......... SIGNIFICANT INFORMATION GAINED!'
           write(6,*)
           matclust(0)=matclust(0)+1
           ipoint=matclust(0)
           matclust(ipoint)=imin
           ilast=imin
           flag1=.true.
C
           call compred(ivec,matclust,nres,nam,ntm,percomp,redind,flag2)
C
           if (flag2) then
C
             write(6,*)
             write(6,*) '.......... THE SET IS TOO REDUNDANT!'
             write(6,*) '.......... DELETING THE LAST ANALYZED EIGENVECT
     &OR AND STOPPING THE SELECTION PROCESS!'
             write(6,*) 
             write(6,*)
             write(6,*)
C
             matclust(ipoint)=0
             matclust(0)=matclust(0)-1
             flag1=.false.
             ilast=0
             realp=realp_old
             cont=cont_old
             call copy_ichk2s(ichk2_old,ichk2,nres)
           end if
         else
           write(6,*)
           write(6,*) '.......... NO SIGNIFICANT INFORMATION GAINED!'
           write(6,*) '.......... ANALIZING ANOTHER EIGENVECTOR!'
           write(6,*)
           realp=realp_old
           cont=cont_old
           call copy_ichk2s(ichk2_old,ichk2,nres)
         end if
       end if
       write(6,*)
       return
      end


C
C Subroutine to construct the array of the non-covered components
C
      Subroutine noncovered(ichk2,missing,nres)
       implicit double precision (a-h,o-z)
       dimension ichk2(nres),missing(0:nres)
C
       call initialize(missing,nres+1)
       do i=1,nres
         if (ichk2(i) .eq. 0) then
           missing(0)=missing(0)+1
           jpoint=missing(0)
           missing(jpoint)=i
         end if
       end do   
       return
      end

C
C Subroutine to copy the ichk2 arrays (ic1 into ic2)
C
      Subroutine copy_ichk2s(ic1,ic2,nres)
       implicit double precision (a-h,o-z)
       dimension ic1(nres),ic2(nres)
C
       do i=1,nres
         ic2(i)=ic1(i)
       end do
       return
      end

C
C Subroutine to reconstruct the energy interaction matrix
C
      Subroutine rec_ene(evec,eigval,matclust,kp,energy,ifreq,cpoint,
     &                   nres,nam,ntr,nb)
       implicit double precision (a-h,o-z)
       dimension evec(nres,nres),eigval(nres),matclust(0:nam),kp(ntr),
     &           energy(ntr),ifreq(nb),cpoint(nb+1)
       kp2(ii,jj)=kp(max(ii,jj))+(ii+jj-max(ii,jj))
C
       num=matclust(0)
       call dinitialize(energy,ntr)
       vmin=10000.0d0
       vmax=-10000.0d0
       do i=1,nres
         do j=i,nres
           ind=kp2(i,j)
           do k=1,num
             kr=matclust(k)
             energy(ind)=energy(ind)+evec(i,kr)*eigval(kr)*
     &                               evec(j,kr)
           end do
C 
           if (energy(ind) .gt. vmax) then
             vmax=energy(ind)
           end if
           if (energy(ind) .lt. vmin) then
             vmin=energy(ind)
           end if
         end do
       end do 
C
       write(6,*)
       write(6,*) 'MINIMUM ENERGY VALUE = ',vmin
       write(6,*) 'MAXIMUM ENERGY VALUE = ',vmax
       write(6,*)
       call binning(kp,energy,ifreq,cpoint,ntr,nb,nres,vmin,vmax)
C 
C Writing the ENERGY MATRIX for GNUPLOT
C
       do i=1,nres
         do j=1,nres
           ind=kp2(i,j)
           write(33,*) i,j,energy(ind)
         end do
         write(33,*)
       end do
       return
      end

C
C Subroutine for the "blocking" of the reconstructed interaction energy matrrix
C
      Subroutine blocking(eigval,kp,energy,benergy,nres,ntr,denstot)
       implicit double precision (a-h,o-z)
       dimension eigval(nres),kp(ntr),energy(ntr),benergy(ntr)
       kp2(ii,jj)=kp(max(ii,jj))+(ii+jj-max(ii,jj))
C
       vmed1=abs(eigval(1)/nres)                                        !Determining the threshold for the "Energy Matrix Blocking"
       write(6,*) 'INTERACTION ENERGY MATRIX THRESHOLD: ',vmed1
       write(6,*)
C      
       icont=0 
       one=1.0d0
       zero=0.0d0
       do i=1,nres
         do j=1,nres
           ind=kp2(i,j)
           if (abs(energy(ind)) .gt. vmed1) then
             benergy(ind)=one
             icont=icont+1
             write(34,*) i,j,one
           else
             benergy(ind)=zero
             write(34,*) i,j,zero
           end if
         end do
         write(34,*)
       end do
       denstot=(icont*1.0d0)/(nres*nres)
       write(6,*) 'TOTAL DENSITY; ',denstot
       write(6,*)
       write(6,*) 'THRESHOLD: ',denstot
       write(6,*)
       return
      end

C
C Subroutine to construct the starting diagonal tesserae
C
      Subroutine buildtes(ktes,ndiag,nres,ngrain)
       implicit double precision (a-h,o-z)
       dimension ktes(ndiag,0:nres)
C
       call initialize(ktes,ndiag*(nres+1))
       do i=1,ndiag
         if (i .lt. ndiag) then
           ktes(i,0)=ngrain
           istart=(i-1)*ngrain+1
           iend=ndiag*ngrain
           icont=1
           do j=istart,iend
             ktes(i,icont)=j
             icont=icont+1
           end do
         else
           icont=1
           ktes(i,0)=nres-(ndiag-1)*ngrain           
           istart=(ndiag-1)*ngrain+1
           do j=istart,nres
             ktes(i,icont)=j
             icont=icont+1
           end do
         end if
       end do
       return
      end

C
C Subroutine to compute the "Density" of the starting diagonal tesserae
C
      Subroutine diagdens(kp,benergy,ktes,dens,ntr,ntrb,ndiag,nres)
       implicit double precision (a-h,o-z)
       dimension kp(ntr),benergy(ntrb),ktes(ndiag,0:nres),dens(ndiag)
       kp2(ii,jj)=kp(max(ii,jj))+(ii+jj-max(ii,jj))
C
       call dinitialize(dens,ndiag)
       do k=1,ndiag
         nn=ktes(k,0)
         nfav=0
         ntot=0
         do i=1,nn
           ir=ktes(k,i)
           do j=1,nn
             jr=ktes(k,j)
             ntot=ntot+1
             ind=kp2(ir,jr)
             if (benergy(ind) .eq. 1) then
               nfav=nfav+1
             end if
           end do
         end do
         dens(k)=(nfav*1.0d0)/ntot
       end do
       return
      end

C
C Subroutine to clusterize consecutive diagonal tesserae
C (where it is possible)
C
      Subroutine cluster1(kp,benergy,ktes,dens,isl,ntr,ntrb,ndiag,nres,
     &                    denstot,nclust)
       implicit double precision (a-h,o-z)
       dimension kp(ntr),benergy(ntrb),ktes(ndiag,0:nres),dens(ndiag),
     &           isl(ndiag,0:nres)
       logical   flagtes
C
       call initialize(isl,ndiag*(nres+1))
       istart=1
       iclust=0
C
       do i=1,ndiag
         if (i .eq. istart) then
           if (dens(i) .ge. denstot) then
             iclust=iclust+1
             call updateclust(ktes,isl,ndiag,nres,i,iclust)             !Updating the cluster of tesserae (new cluster): i ----> iclust 
           else
             istart=i+1                                            
           end if
         else
           if (dens(i) .ge. denstot) then
             flagtes=.false.
             call interaction1(kp,benergy,ktes,isl,ntr,ntrb,ndiag,nres, !Computing the tessera-cluster "interaction" (i vs. iclust)
     &                         i,iclust,denstot,flagtes)    
             if (flagtes) then
               call updateclust(ktes,isl,ndiag,nres,i,iclust)           !Updating the cluster of tesserae: i ----> iclust
             else
               iclust=iclust+1
               call updateclust(ktes,isl,ndiag,nres,i,iclust)           !Updating the cluster of tesserae (new cluster): i ----> iclust
             end if
           else
             istart=i+1
           end if
         end if
       end do
       nclust=iclust
       return
      end

C
C Subroutine to update the cluster of tesserae
C
      Subroutine updateclust(ktes,isl,ndiag,nres,i,iclust)
       implicit double precision (a-h,o-z)
       dimension ktes(ndiag,0:nres),isl(ndiag,0:nres)
C
       num=ktes(i,0)
       nprev=isl(iclust,0)
       isl(iclust,0)=isl(iclust,0)+num
       ncurr=isl(iclust,0)
       icont=0
       do k=nprev+1,ncurr
         icont=icont+1
         isl(iclust,k)=ktes(i,icont)
       end do
       return
      end

C
C Subroutine to compute the interaction between the cluster in construction
C and the diagonal tessera in exam
C
      Subroutine interaction1(kp,benergy,ktes,isl,ntr,ntrb,ndiag,nres,i,
     &                        iclust,denstot,flagtes)
       implicit double precision (a-h,o-z)
       dimension kp(ntr),benergy(ntrb),ktes(ndiag,0:nres),
     &           isl(ndiag,0:nres)
       logical   flagtes
       kp2(ii,jj)=kp(max(ii,jj))+(ii+jj-max(ii,jj))
C
       ifav=0
       itot=0
       do j=1,ktes(i,0)
         jr=ktes(i,j)
         do k=1,isl(iclust,0)
           kr=isl(iclust,k)
           ind=kp2(jr,kr)
           if (benergy(ind) .eq. 1) then
             ifav=ifav+1
           end if
           itot=itot+1
         end do
       end do
       valint=(ifav*1.0d0)/itot      
       if (valint .ge. denstot) then
         flagtes=.true.
       end if
       return
      end      
          
C
C Subroutine to compute the matrix of the "Density-based" interactions
C between clusters
C 
      Subroutine comp_dbim(kp,benergy,isl,dbim,ntr,ntrb,ndiag,nres,ntr2,
     &                     nclust)
       implicit double precision (a-h,o-z)
       dimension kp(ntr),benergy(ntrb),isl(ndiag,0:nres),dbim(ntr2)
       kp2(ii,jj)=kp(max(ii,jj))+(ii+jj-max(ii,jj))
C
       do i=1,nclust
         do j=i+1,nclust
           if ((isl(i,0) .ne. 0) .and. (isl(j,0) .ne. 0)) then
             call interaction2(kp,benergy,isl,ntr,ntrb,ndiag,nres,i,j,  !Computing the interaction between the clusters i and j
     &                         vdens)
             ind2=kp2(i,j)
             dbim(ind2)=vdens
           end if
         end do
       end do
       return
      end

C
C Subroutine to compute the interaction beteen the clusters i and j
C
      Subroutine interaction2(kp,benergy,isl,ntr,ntrb,ndiag,nres,i,j,
     &                        vdens)
       implicit double precision (a-h,o-z)
       dimension kp(ntr),benergy(ntrb),isl(ndiag,0:nres)
       kp2(ii,jj)=kp(max(ii,jj))+(ii+jj-max(ii,jj))
C
       imax=isl(i,0)
       jmax=isl(j,0)
       ifav=0
       itot=0
       do ic=1,imax
         ir=isl(i,ic)
         do jc=1,jmax
           jr=isl(j,jc)
           ind=kp2(ir,jr)
           if (benergy(ind) .eq. 1) then
             ifav=ifav+1
           end if
           itot=itot+1
         end do
       end do
       vdens=(ifav*1.0d0)/itot
       return
      end

C
C Subroutine to perform further clusterizations of the obtained blocks
C (until convergence)
C
      Subroutine cluster_conv(kp,benergy,isl,dbim,list,ntr,ntrb,ndiag,
     &                        nres,ntr2,nclust,denstot)
       implicit double precision (a-h,o-z)
       dimension kp(ntr),benergy(ntrb),isl(ndiag,0:nres),dbim(ntr2),
     &           list(nclust)
C         
 340   nexch=0
       call dinitialize(dbim,ntr2)
       call initialize(list,nclust)
C
C Computing the matrix of the "Density-based" interactions between clusters
C
       call comp_dbim(kp,benergy,isl,dbim,ntr,ntrb,ndiag,nres,ntr2,
     &                nclust)
C
       do i=1,nclust
         if (isl(i,0) .ne. 0) then
           if (list(i) .eq. 1) goto 341
           call maxinter(kp,dbim,ntr,ntr2,i,jmax,nclust,denstot)
C
           if (jmax .ne. 0) then                                        !Checking if the cluster i maximally interacts with the cluster jmax
             if (list(jmax) .eq. 1) goto 341
             call maxinter(kp,dbim,ntr,ntr2,jmax,imax,nclust,denstot)
             if (imax .eq. i) then
               nexch=nexch+1
               call update_list(list,nclust,i,jmax)                     !Updating the list of the already considered clusters
               call cluster2(isl,ndiag,nres,i,jmax)                     !Joining the clusters i and jmax: jmax ----> i
               call deletion(isl,ndiag,nres,jmax)                       !Deleting the cluster jmax
             end if
           end if
         end if
 341     continue
       end do
       if (nexch .ne. 0) goto 340
       return
      end

C
C Subroutine to determine the cluster that maximally interacts with the i-th one
C
      Subroutine maxinter(kp,dbim,ntr,ntr2,i,jmax,nclust,denstot)
       implicit double precision (a-h,o-z)
       dimension kp(ntr),dbim(ntr2)
       kp2(ii,jj)=kp(max(ii,jj))+(ii+jj-max(ii,jj))
C
       vmax=0.0d0
       jmax=0
       do j=1,nclust
         ind=kp2(i,j)
         value=dbim(ind)
         if ((value .ge. denstot) .and. (value .gt. vmax)) then
           vmax=value
           jmax=j
         end if
       end do
       return
      end

C
C Subroutine to join the clusters i and jmax (jmax ----> i)
C
      Subroutine cluster2(isl,ndiag,nres,i,jmax)
       implicit double precision (a-h,o-z)
       dimension isl(ndiag,0:nres)
C
       nprev=isl(i,0)
       nadd=isl(jmax,0)
       ncurr=nprev+nadd
       isl(i,0)=ncurr
       icont=0
       do k=nprev+1,ncurr
         icont=icont+1
         isl(i,k)=isl(jmax,icont)
       end do
       return
      end   

C
C Subrotine to update the list of clusters already considered in the
C new clsuterization
C
      Subroutine update_list(list,nclust,i,jmax)
       implicit double precision (a-h,o-z)
       dimension list(nclust)
C
       list(i)=1
       list(jmax)=1
       return
      end

C
C Subrutine to delete the cluster jmax (just clsterized with cluster i)
C
      Subroutine deletion(isl,ndiag,nres,jmax)
       implicit double precision (a-h,o-z)
       dimension isl(ndiag,0:nres)
C
       mm=isl(jmax,0)
       do kk=0,mm
         isl(jmax,kk)=0
       end do
       return
      end

C
C Subroutine to check if the domains satisfy the minimal length requirement
C
      Subroutine minimal(isl,list,ndiag,nres,nclust,nct,length)
       implicit double precision (a-h,o-z)
       dimension isl(ndiag,0:nres),list(nclust)
C
       nct=0
       call initialize(list,nclust)
C
       do i=1,nclust
         num=isl(i,0)
         if (num .gt. 0) then
           if (num .ge. length) then
             nct=nct+1
             list(nct)=i
           else                                                         !Deleting the "short" domains
             do j=0,num
               isl(i,j)=0
             end do
           end if
         end if
       end do
       return
      end
          
C
C Subroutine to copy the domains residue indexes in idom (isl ----> idom)
C
      Subroutine copy_dom(isl,list,idom,ndiag,nres,nclust,nct)
       implicit double precision (a-h,o-z)
       dimension isl(ndiag,0:nres),list(nclust),idom(nct,0:nres)
C
       do k=1,nct
         i=list(k)
         num=isl(i,0)
         do j=0,num
           idom(k,j)=isl(i,j)
         end do
       end do
       return
      end

C
C Subroutine to order the residue indexes in idom 
C
      Subroutine order_dom(idom,nct,nres)
       implicit double precision (a-h,o-z)   
       dimension idom(nct,0:nres)
C
       do k=1,nct
         num=idom(k,0)
         do i=1,num-1
           do j=i+1,num
             if (idom(k,j) .lt. idom(k,i)) then
               iapp=idom(k,j)
               idom(k,j)=idom(k,i)
               idom(k,i)=iapp
             end if
           end do
         end do
       end do
       return
      end

C
C Subroutine to fill the gaps in the domains
C
      Subroutine turkey(isl,list,idom,ndiag,nres,nclust,nct)
       implicit double precision (a-h,o-z)
       dimension isl(ndiag,0:nres),list(nclust),idom(nct,0:nres)
       logical   flagfil
C
       do k=1,nct
         num=idom(k,0)
         nnew=num
         do i=2,num
           istart=idom(k,i-1)+1
           iend=idom(k,i)-1
           istep=idom(k,i)-(idom(k,i-1)+1)
           if (istep .gt. 0) then
             flagfil=.false.
             do j=1,nct
               if (j .ne. k) then
                 jclust=list(j)
                 call checkfil(isl,ndiag,nres,jclust,istart,iend,       !Checking if the detected gap is a part of another domain
     &                         flagfil)
                 if (flagfil) goto 342
               end if
             end do
             nold=nnew
             nnew=nold+istep
             call filling(idom,nct,nres,k,nold,nnew,istart)             !Filling the detected gap
 342         continue
           end if
         end do
         idom(k,0)=nnew
       end do
       return
      end
    
C
C Subroutine to check if the detected gap is a part of another domain
C
      Subroutine checkfil(isl,ndiag,nres,jclust,istart,iend,flagfil)
       implicit double precision (a-h,o-z)
       dimension isl(ndiag,0:nres)
       logical flagfil
C
       num2=isl(jclust,0)
       do m1=istart,iend
         do m2=1,num2
           if (isl(jclust,m2) .eq. m1) then
             flagfil=.true.
             goto 343
           end if
         end do         
       end do
 343   continue
       return
      end

C
C Subroutine to fill the detected gap
C
      Subroutine filling(idom,nct,nres,k,nold,nnew,istart)
       implicit double precision (a-h,o-z)
       dimension idom(nct,0:nres)
C
       icont=0
       do i=nold+1,nnew
         idom(k,i)=istart+icont
         icont=icont+1
       end do
       return
      end

C
C Subroutine to construct the iact array
C
      Subroutine build_iact(idom,iact,nct,nres,nctmax,minl)
       implicit double precision (a-h,o-z)
       dimension idom(nct,0:nres),iact(nctmax)
C
       do i=1,nct
         if (idom(i,0) .ge. minl) then
           iact(i)=1
         end if
       end do
       return
      end

C
C Subroutine to sum the elements of the iact array
C
      Subroutine sum_iact(iact,nctmax,nctprv,jsm)
       implicit double precision (a-h,o-z)
       dimension iact(nctmax)
C
       jsm=0
       do i=1,nctprv
         jsm=jsm+iact(i)
       end do
       return
      end

C
C Subroutine to construct the starting kpoint array
C
      Subroutine build_kpnt(kpoint,nctprv)
       implicit double precision (a-h,o-z)
       dimension kpoint(nctprv)
C
       do i=1,nctprv
         kpoint(i)=i
       end do
       return
      end   

C
C Subroutine to copy idom in newdom (if nstep=1)
C 
      Subroutine copy_idom(idom,newdom,nct,nres,nctmax)
       implicit double precision (a-h,o-z)
       dimension idom(nct,0:nres),newdom(nctmax,0:nres)
C
       do i=1,nct
         kk=idom(i,0)
         do j=0,kk
           newdom(i,j)=idom(i,j)
         end do
       end do         
       return
      end

C
C Subroutine to assign the values to jpt and active
C
      Subroutine recindx(iact,kpoint,nctmax,nctprv,nn,jpt,active)
       implicit double precision (a-h,o-z)
       dimension iact(nctmax),kpoint(nctprv)
       logical   active
C
       jpt=kpoint(nn)
       if (iact(jpt) .eq. 1) then
         active=.true.
       end if
       return
      end

C
C Subroutine to recover the dimensions of the domain in exam
C
      Subroutine recdim(newdom,nctmax,nres,jpt,ndim)
       implicit double precision (a-h,o-z)
       dimension newdom(nctmax,0:nres)
C
       ndim=newdom(jpt,0)
       return
      end
C
C Subroutine to extract bmini from benergy 
C
      Subroutine extract_bmini(kp,benergy,newdom,bmini,ntr,nctmax,nres,
     &                         ntr3,jpt,ndim,dt2)
       implicit double precision (a-h,o-z)
       dimension kp(ntr),benergy(ntr),newdom(nctmax,0:nres),bmini(ntr3)
       kp2(ii,jj)=kp(max(ii,jj))+(ii+jj-max(ii,jj))
C
       jjmax=newdom(jpt,0)
       icont=0
       do i=1,jjmax
         ir=newdom(jpt,i)
         do j=1,jjmax
           jr=newdom(jpt,j)
           indr=kp2(ir,jr)       
           indm=kp2(i,j)
           bmini(indm)=benergy(indr)
           if (bmini(indm) .eq. 1.0d0) then
             icont=icont+1
           end if
         end do
       end do
       dt2=(icont*1.0d0)/(ndim*ndim)
       return
      end

C
C Subroutine to update the iact array (only if nct2 < 2)
C
      Subroutine updating1(iact,nctmax,jpt)
       implicit double precision (a-h,o-z)
       dimension iact(nctmax)
C
       iact(jpt)=0
      return
      end

C
C Subroutine to copy the nn-th row of newdom into nnap
C
      Subroutine copy2nnap(newdom,nnap,nctmax,nres,jpt)
       implicit double precision (a-h,o-z)
       dimension newdom(nctmax,0:nres),nnap(nres)
C
       lmax=newdom(jpt,0)
       do l=1,lmax
         nnap(l)=newdom(jpt,l)
       end do
       return
      end   

C
C Subroutine to update fundamental arrays: iact, newdom and kpoint (if nct2 >= 2)
C
      Subroutine updating2(iact,newdom,kpoint,idom2,nnap,nctmax,nres,
     &                     nctprv,nct2,ndim,nn,minl,nprov)
       implicit double precision (a-h,o-z)
       dimension iact(nctmax),newdom(nctmax,0:nres),kpoint(nctprv),
     &           idom2(nct2,0:ndim),nnap(nres)
C
       jpt=kpoint(nn)
C
       if (jpt .lt. nprov) then
         call shift_iact(iact,nctmax,nctprv,jpt,nct2)                   !Shifting the elements of the iact array
         call shift_nwdm(newdom,nctmax,nres,nctprv,jpt,nct2)            !Shifting the rows of newdom
         call update_kpoint(kpoint,nctprv,nn,nct2)                      !Updating the kpoint array 
       end if
C
       call update_nwdm(newdom,idom2,nnap,nctmax,nres,nct2,ndim,jpt)    !Updating newdom
       call update_iact(iact,newdom,nctmax,nres,jpt,nct2,minl)          !Updating the iact array
       return
      end

C
C Subroutine to shift the elements of the iact array
C
      Subroutine shift_iact(iact,nctmax,nctprv,jpt,nct2)
       implicit double precision (a-h,o-z)
       dimension iact(nctmax)
C
       ks=nct2-1
       do j=nctprv,jpt+1,-1
         iact(j+ks)=iact(j)
       end do
       return
      end

C
C Subroutine to shift the rows of newdom
C 
      Subroutine shift_nwdm(newdom,nctmax,nres,nctprv,jpt,nct2)
       implicit double precision (a,h,o-z)
       dimension newdom(nctmax,0:nres)
C
       ks=nct2-1
       do j=nctprv,jpt+1,-1
         kmax=newdom(j,0)
         do k=0,kmax
           newdom(j+ks,k)=newdom(j,k)
         end do
       end do
       return
      end        

C
C Subroutine to update the kpoint array
C
      Subroutine update_kpoint(kpoint,nctprv,nn,nct2)
       implicit double precision (a-h,o-z)
       dimension kpoint(nctprv)
C
       ks=nct2-1
       do j=nn+1,nctprv
         kpoint(j)=kpoint(j)+ks
       end do
       return
      end

C
C Subroutine to update newdom 
C
      Subroutine update_nwdm(newdom,idom2,nnap,nctmax,nres,nct2,ndim,
     &                       jpt)
       implicit double precision (a-h,o-z) 
       dimension newdom(nctmax,0:nres),idom2(nct2,0:ndim),nnap(nres)
C
       do k=1,nct2
         num=idom2(k,0)
         newdom(jpt+k-1,0)=num
         do j=1,num
           jr=idom2(k,j)
           newdom(jpt+k-1,j)=nnap(jr)
         end do 
         write(6,*)
       end do 
       return
      end

C
C Subroutine to update the iact array
C
      Subroutine update_iact(iact,newdom,nctmax,nres,jpt,nct2,minl)
       implicit double precision (a-h,o-z)
       dimension iact(nctmax),newdom(nctmax,0:nres)
C
       ks=nct2-1
       do j=jpt,jpt+ks
         if (newdom(j,0) .ge. minl) then
           iact(j)=1
         else
           iact(j)=0
         end if
       end do
       return
      end

C
C Subroutine to create the vector kp
C
      Subroutine ivett(kp,ntr)
       implicit double precision (a-h,o-z)
       dimension kp(ntr)
C
       do i=1,ntr
         kp(i)=i*(i-1)/2
       end do
       return
      end

C
C Subroutine to write the domains in a more compact way
C
      Subroutine compact(idom,intv,nctm,nres,nctr)
       implicit double precision (a-h,o-z)
       dimension idom(nctm,0:nres),intv(nctm,0:nres)
C
       call initialize(intv,nctm*(nres+1))
C
       do k=1,nctr
         icouple=0
         istart=idom(k,1)
         nlast=idom(k,0)
         do i=2,nlast
           iprev=idom(k,i-1)
           icurr=idom(k,i)
           idiff=icurr-iprev
           if (idiff .gt. 1) then
             ilast=iprev
             icouple=icouple+1
             ipoint=2*(icouple-1)+1
             intv(k,ipoint)=istart
             intv(k,ipoint+1)=ilast
             istart=icurr
           end if
           if (i .eq. nlast) then
             ilast=icurr
             icouple=icouple+1
             ipoint=2*(icouple-1)+1
             intv(k,ipoint)=istart
             intv(k,ipoint+1)=ilast
           end if
         end do 
         intv(k,0)=icouple
       end do
C
       do k=1,nctr
         write(6,*)
         write(6,*) 'DOMAIN NUMBER ',k
         do i=1,intv(k,0)
           ipoint=2*(i-1)+1
           write(6,*),intv(k,ipoint),intv(k,ipoint+1)
         end do
       end do
       return
      end

C
C Subroutine to delete the NGRAIN-residue clusters in the domains
C (if they constitute less the 10% of the domain in exam)
C
      Subroutine fiveres(intv,nctm,nres,ngrain,nctr)
       implicit double precision (a-h,o-z)
       dimension intv(nctm,0:nres)
C
       do i=1,nctr
         idm=0
         num=intv(i,0)
C
C Computing the dimension of the domain
C
         do j=1,num
           jpoint=2*(j-1)+1
           jstart=intv(i,jpoint)
           jend=intv(i,jpoint+1)
           jdm=jend-jstart+1
           idm=idm+jdm
         end do
C
         frac=ngrain*1.0d0/idm
C
         if (frac .lt. 0.1d0) then
 555       continue
           do j=1,num
             jpoint=2*(j-1)+1
             jstart=intv(i,jpoint)
             jend=intv(i,jpoint+1)
             jdm=jend-jstart+1
             if (jdm .le. ngrain) then
               intv(i,0)=intv(i,0)-1
               do k=j,num
                 kpoint=2*(k-1)+1
                 intv(i,kpoint)=intv(i,kpoint+2)
                 intv(i,kpoint+1)=intv(i,kpoint+3)
               end do
               num=num-1
               goto 555
             end if
           end do     
         end if 
       end do
       return
      end  



C
C Subroutine to read the contacts matrix
C
      Subroutine readcontact(matcont,nres)
       implicit double precision (a-h,o-z)
       dimension matcont(nres,nres)
C
       do i=1,nres
         do j=1,nres
           read(35,*) ia,jb,matcont(i,j)
         end do
         read(35,*)
       end do
       return
      end

C
C Subroutine to determine the small clusters in the domains
C
      Subroutine smallclust(intv,indx,nctm,nres,nctmax,nctr,length,
     &                      nsmall)
       implicit double precision (a-h,o-z)
       dimension intv(nctm,0:nres),indx(nctmax,2)
C
       nsmall=0
C
       do k=1,nctr
         do i=1,intv(k,0)
           ipoint=2*(i-1)+1
           idiff=intv(k,ipoint+1)-intv(k,ipoint)+1
           if (idiff .lt. length) then
             nsmall=nsmall+1
             indx(nsmall,1)=k
             indx(nsmall,2)=i
           end if
         end do
       end do
       return
      end

C
C Subroutine to compute the domain where to move the small cluster 
C
      Subroutine denscont(intv,matcont,indx,nctmax,nres,nctr,k,kdom,
     &                    length,move)
       implicit double precision (a-h,o-z)
       dimension intv(nctmax,0:nres),matcont(nres,nres),indx(nctmax,2)
C
       vmaxden=-100000.0d0
       kdom=indx(k,1)
       kclu=indx(k,2)
       kpoint=2*(kclu-1)+1
       kstart=intv(kdom,kpoint)
       kend=intv(kdom,kpoint+1)
       move=kdom
C
       do i=1,nctr
         vok=0.0d0
         vtot=0.0d0
         if (i .ne. kdom) then
           do j=1,intv(i,0)
             jpoint=2*(j-1)+1
             jstart=intv(i,jpoint)
             jend=intv(i,jpoint+1)
             ilen=jend-jstart+1
             if (ilen .gt. length) then
               do kk=kstart,kend
                 do jj=jstart,jend
                   if (matcont(kk,jj) .eq. 1) then
                     vok=vok+1.0d0
                   end if
                   vtot=vtot+1.0d0
                 end do
               end do
             end if
           end do
           if (vtot .ne. 0.0d0) then
             vint=vok/vtot
           else
             vint=-100001.0d0
           end if
           if (vint .gt. vmaxden) then
             vmaxden=vint
             move=i
           end if
         else
           do j=1,intv(i,0)
             if (j .ne. kclu) then
               jpoint=2*(j-1)+1
               jstart=intv(i,jpoint)
               jend=intv(i,jpoint+1)
               ilen=jend-jstart+1
               if (ilen .gt. length) then
                 do kk=kstart,kend
                   do jj=jstart,jend
                     if (matcont(kk,jj) .eq. 1) then
                       vok=vok+1.0d0
                     end if
                     vtot=vtot+1.0d0
                   end do
                 end do
               end if 
             end if
           end do
           if (vtot .ne. 0.0d0) then
             vint=vok/vtot
           else
             vint=-100001.0d0
           end if
           if (vint .gt. vmaxden) then
             vmaxden=vint
             move=i
           end if
         end if
       end do
       return
      end

C
C Subroutine to move the selected small cluster to the selected domain
C
      Subroutine change(intv2,indx,nctmax,nres,k,move)
       implicit double precision (a-h,o-z)
       dimension intv2(nctmax,0:nres),indx(nctmax,2)
C
       intv2(move,0)=intv2(move,0)+1
       mclu=intv2(move,0)
       mpoint=2*(mclu-1)+1
C
       kdom=indx(k,1)
       kclu=indx(k,2)
       kpoint=2*(kclu-1)+1
C
       intv2(move,mpoint)=intv2(kdom,kpoint)
       intv2(move,mpoint+1)=intv2(kdom,kpoint+1)
C
       knum=intv2(kdom,0)
       kmax=2*(knum-1)+1
       if (kpoint .lt. kmax) then
         do jk=kpoint,kmax+1
           intv2(kdom,jk)=intv2(kdom,jk+2)
         end do
         intv2(kdom,0)=intv2(kdom,0)-1
       else
         intv2(kdom,0)=intv2(kdom,0)-1
         intv2(kdom,kpoint)=0
         intv2(kdom,kpoint+1)=0
       end if
       return
      end

C
C Suibroutine to check if the new domains satisfy the minimum 
C length requirement
C      
      Subroutine minreq(intv2,nctmax,nres,nctprv,length)
       implicit double precision (a-h,o-z)
       dimension intv2(nctmax,0:nres)
C
       do i=1,nctprv
         numres=0
         do j=1,intv2(i,0)
           jpoint=2*(j-1)+1
           jstart=intv2(i,jpoint)
           jend=intv2(i,jpoint+1)
           numres=numres+jend-jstart+1
         end do
C
         if (numres .lt. length) then
           do j=0,nres
             intv2(i,j)=0
           end do
         end if
       end do
       return
      end
 
C
C Subroutine to create islapp and list from intv2
C
      Subroutine creating(intv2,islapp,list,nctmax,nres,nctprv,ndnew)
       implicit double precision (a-h,o-z)
       dimension intv2(nctmax,0:nres),islapp(nctprv,0:nres),list(nctprv)
C
       ndnew=0
       do i=1,nctprv
         num=intv2(i,0)
         if (num .ne. 0) then
           nprog=0
           do j=1,num
             jpoint=2*(j-1)+1
             jstart=intv2(i,jpoint)
             jend=intv2(i,jpoint+1)
             do k=jstart,jend
               nprog=nprog+1
               islapp(i,nprog)=k
             end do
           end do
           islapp(i,0)=nprog
C
           ndnew=ndnew+1
           list(ndnew)=i
         end if
       end do
       return
      end



      Subroutine binning(kp,energy,ifreq,cpoint,ntr,nb,nres,vmin,vmax)
       implicit double precision (a-h,o-z)
       dimension kp(ntr),energy(ntr),ifreq(nb),cpoint(nb+1)
       kp2(ii,jj)=kp(max(ii,jj))+(ii+jj-max(ii,jj))
C
       call initialize(ifreq,nb)
       step=abs(vmax-vmin)/nb
       cpoint(1)=vmin
       cpoint(nb+1)=vmax
C
       do i=2,nb
         cpoint(i)=cpoint(i-1)+step
       end do
C
       do i=1,nres
         do j=i,nres
           ind=kp2(i,j)
           if (energy(ind) .eq. vmax) then
             ifreq(nb)=ifreq(nb)+1
           else
             do k=1,nb
               rmin=cpoint(k)
               rmax=cpoint(k+1)
               ene=energy(ind)
               if ((ene .ge. rmin) .and. (ene .lt. rmax)) then
                 ifreq(k)=ifreq(k)+1
               end if
             end do
           end if
         end do
       end do
C
       write(6,*) 'BINNING FOR GNUPLOT REPRESENTATION:'
       do i=1,nb
         write(6,*) cpoint(i),cpoint(i+1),ifreq(i)
       end do
       write(6,*)
       return
      end

      Subroutine dinitialize(vect,n)
       implicit double precision (a-h,o-z)
       dimension vect(n)
C
       do i=1,n
         vect(i)=0.0d0
       end do
       return
      end

      Subroutine initialize(ivect,n)
       implicit double precision (a-h,o-z)
       dimension ivect(n)
C
       do i=1,n
         ivect(i)=0
       end do
       return
      end
