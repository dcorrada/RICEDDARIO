#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#define Nmax (1500)
#define Dist(a,b) (sqrt((a[0]-b[0])*(a[0]-b[0])+(a[1]-b[1])*(a[1]-b[1])+(a[2]-b[2])*(a[2]-b[2])))

#define weight(d) ((1.0-tanh((d-6.0)/1.0))/2.0)
main(){

  int i,j, k, l, c, N, m, N_averaging_frames, start_frame, end_frame;
  float x[Nmax][3], ave_dist[Nmax][Nmax], distfluc[Nmax][Nmax];
  float profile[Nmax], num[Nmax], den[Nmax], num2[Nmax], cutoff;
  FILE *fp, *fp2,*fp3, *fp4, *fp5, *fp6;
  char filename[500];

  printf("Number of a.a. in each frame of trajectory trj.xyz? (Max %d)   ",Nmax);
  scanf("%d",&N);

  printf("Index of initial frame? ");
  scanf("%d",&start_frame);
  printf("index of end frame? ");
  scanf("%d",&end_frame);
  printf("cutoff for local flexibility? ");
  scanf("%f",&cutoff);


  fp = fopen("trj.xyz","r");

  sprintf(filename,"rmsdist4gnu_%d_%d.dat",start_frame,end_frame);
  fp4 = fopen(filename,"w");
  
  sprintf(filename,"rmsdist4gnu_scale_%d_%d.dat",start_frame,end_frame);
  fp6 = fopen(filename,"w");
  
 sprintf(filename,"profile.local.distfluc.%f._%d_%d.dat",cutoff,start_frame,end_frame);
      fp5 = fopen(filename,"w"); 
    
  for(i=0; i < N; i++){
    for(j=0; j < N; j++){
      ave_dist[i][j]=0.0;
      distfluc[i][j]=0.0;
    }
  }

  for(i=0; i < N; i++){
    num[i]=0.0; den[i]=0.0; num2[i]=0.0;
  }

  /* throw away the initial frames until you reach the desired starting one */


  for(l=0;l<start_frame ;l++){

    for(i=0; i < N; i++){
      if (fscanf(fp,"%f %f %f",&x[i][0],&x[i][1],&x[i][2])==EOF){
    printf("Premature end of file!");
    exit(1);
      }
    }
  }

  c=0; k=0;
  for(l=start_frame;l <end_frame ;l++){
  
  
    for(i=0; i < N; i++){
      if (fscanf(fp,"%f %f %f",&x[i][0],&x[i][1],&x[i][2])==EOF){
    fclose(fp);
    fclose(fp2);
    fclose(fp3);
    fclose(fp4);
    fclose(fp5);
    fclose(fp6);
    exit(0);
      }
    }
    
    for(i=0; i < N; i++){
      for(j=0; j < N; j++){
    ave_dist[i][j]+=Dist(x[i],x[j]);
      }
    }
    
    k++;
  }
  
    for(i=0; i < N; i++){
      for(j=0; j < N; j++){
    ave_dist[i][j]=ave_dist[i][j]/k;
      }
    }

    /* now we compute instantaneous deviations */
    rewind(fp);

  for(l=0;l<start_frame ;l++){

    for(i=0; i < N; i++){
      if (fscanf(fp,"%f %f %f",&x[i][0],&x[i][1],&x[i][2])==EOF){
    printf("Premature end of file!");
    exit(1);
      }
    }
  }
  k=0;
  for(l=start_frame;l <end_frame ;l++){


    for(i=0; i < N; i++){
      if (fscanf(fp,"%f %f %f",&x[i][0],&x[i][1],&x[i][2])==EOF){
    fclose(fp);
    fclose(fp2);
    fclose(fp3);
    fclose(fp4);
    fclose(fp5);
    fclose(fp6);
    exit(0);
      }
    }
   /*  fprintf(fp5,"MODEL   %2d\n", l); */
    for(i=0; i < N; i++){
     
      for(j=0; j < N; j++){
        if (abs(i-j) <2) continue;
      distfluc[i][j]    += ( Dist(x[i],x[j]) - ave_dist[i][j])*( Dist(x[i],x[j]) - ave_dist[i][j]); }
 /*      num[i] += distfluc[i][j];  }
      
     */
  }
  k++;
  }
  
for(i=0; i < N; i++){m=0;  
      for(j=0; j < N; j++){
     distfluc[i][j]=(distfluc[i][j]/k);
     fprintf(fp4,"%3d %3d %f\n",i+1,j+1,distfluc[i][j]);
    
    
     if (abs(i-j) <2){
     fprintf(fp6,"%3d %3d  0.0\n",i+1,j+1);}
     else{fprintf(fp6,"%3d %3d %f\n",i+1,j+1,distfluc[i][j]/ave_dist[i][j]);
     if (ave_dist[i][j] < cutoff){num[i] += distfluc[i][j];
     m++; }/* printf( "num   %d  %f  %f\n", k, num[i],distfluc[i][j] ) */;
     }
      }
      if(m>0){num[i]= num[i]/m;}else{num[i]=0.;} 
      fprintf(fp5, "%3d  %8.3f\n", i+1,num[i]);
      
      fprintf(fp4,"\n");
      fprintf(fp6,"\n");
    }
    
    }


