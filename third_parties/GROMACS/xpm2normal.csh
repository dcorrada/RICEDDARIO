#! /bin/csh -ef  
#
# Convert an Inner product matrix generated with Gromacs
# into a matrix with numbers
# Isabella Daidone Feb 2002
# La matrice deve essere generata con g_anaeig mattendo: -v "vec[set1]" -v2 "vec[set ref.]"
# In questo modo si ottengon in ascissa i vec[set1] e in ordinata i vec[set ref.].
###################################################################################
if ($#argv < 1) then
echo "ERROR: Missing command line arguments!"
echo "USAGE: extrInPr_averSUM_sqSUM.com Mat1.xpm "
echo
exit -1
endif

cat << _eof_  | gawk  -v Mat1File=$1 -f -   
BEGIN {
        FileComp = "InPr_averSUM_sqSUM.log"
#
#  Defaults variables  
#  
#  FileComp: name of the file for the output 
# 
#
     printf " Matrix of Square Roots of Scalar Products Mij " > FileComp      
     printf "\n" > FileComp  
     printf "  i Vector for the Tunf, j Vector for the Native" > FileComp
     printf "\n" > FileComp 
     printf "\n" > FileComp  
     ini = 1
      while (getline < Mat1File) {
        if ( \$1 == "static" ) {
                 getline <  Mat1File
                 ifi = substr(\$1,2)
#                 ifi = \$2
         }	

         if (substr(\$3,1,1) == "#") {
		   str= \$6
		   gsub(/["]/,"",str)
	           val[substr(\$1,2)] = str
		   labC++
          }
         if (substr(\$1,1,1) == "\"" && NF == 1) {
             x=1
             sum=0   
             sumsum=0
#             printf " %2d",ifi-y > FileComp        
             for(i=ini+1;i<=ifi+1;i++) {  
              k2 = substr(\$0,i,1)
	      map[x,y] = val[k2]
                sum = sum + (map[x,y])*(map[x,y])
                sum1= sum1 + (map[x,y])*(map[x,y])
	        printf " %10.6f",map[x,y] > FileComp  
              x++
	      }
            sqsum= sqrt(sum)
	    printf "\n" > FileComp 
	    y++
            z=ifi-y
            sum=0
            
            }
         }
             sumaver=sum1/ifi
             sqsumaver=sqrt(sumaver)
             printf "\n" > FileComp
             printf "sqsumaver: %10.6f", sqsumaver > FileComp
}
_eof_

exit -1
        
