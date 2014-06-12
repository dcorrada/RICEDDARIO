      subroutine prmtg_ ( a, lda, nr, nc, titolo)
c
c     MS.(24.09.96)
c             Stampa una matrice rettangolare
c
      implicit double precision (a-h,o-z)
      logical logic132
      common /cmnprm_ / logic132
      character *(*) titolo
      dimension a(lda,*)
      dimension ibuffer(12)
5     write(6,*) ' '
      write(6,*) titolo
      write(6,*) ' '
      icolp = 6
      if(logic132) icolp=12
      icoli=1
      icolf=icolp
10    if (nc.lt.icolf) icolf=nc
      icont = 1
      do k=icoli,icolf
         ibuffer(icont) = k
         icont = icont + 1
      end do
      if(logic132) then
         write(6,910) (ibuffer(j),j=1,icont-1)
      else
         write(6,899) (ibuffer(j),j=1,icont-1)
      end if
      do j=1,nr
         if(logic132) then
            write(6,911) j,(a(j,k),k=icoli,icolf)
         else
            write(6,900) j,(a(j,k),k=icoli,icolf)
         end if
      end do
c
c     Formati per la stampa a 80 colonne
c
899   format(/,4X,6(4X,I3,4x))
900   format(1x,I3,6(1X,D10.4))
c
c     Formati per la stampa a 132 colonne
c
910   format(/,4X,12(4X,I3,4x))
911   format(1x,I3,12(1X,D10.4))
      icoli = icolf + 1
      if (icoli .gt. nc) return
      icolf = icoli + icolp - 1
      goto 10
      end
