substr($1,1,1) != "#" && substr($1,1,1) !="@" { i++; eigv[i]=$2;tr+=$2 }
END {
for (k=1;k<=i;k++) {
     sum+=eigv[k]
     printf "%d %f\n",k,sum/tr}
    }

