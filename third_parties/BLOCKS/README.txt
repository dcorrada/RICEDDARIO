********************************************************************************
BLOCKS
release 14.7

Copyright (c) 2014, Alessandro GENONI <ale.genoni@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************
This program is aimed to subdivide a protein in its domain, considering the 
analysis of the eigenvextors of the non-bonded interaction energy matrix. 

Whenever you will use BLOCKS for your work, please cite the following reference:

    Tiana G, Simona F, De Mori G, Broglia R, Colombo G. Protein Sci. 2004;13(1):113-24
    Genoni A, Morra G, Colombo G. J Phys Chem B. 2012;116(10):3331-43


1. SOURCE CODE AND EXECUTABLE FILE

The source code is in the subdirectrory "src". In order to compile a new 
version of BLOCKS type the following:

    $ cd BLOCKS
    $ gfortran -o blocks ./src/blocks.f ./src/subutil.f

2. A NOTE ABOUT THE OUTPUT FILE

The program provides different levels of subdivision into domains. It stops 
only when each domain cannot be further subdivided! The user can choose the 
best one among the proposed ones.

The program also provides a refinement of the determined domains using the 
contacts matrix. However, this is only temporary and it will be dismissed in 
the next version of the program.

3. A NOTE ABOUT THE GNUPLOT INPUT FILES

    gnuplot.inp   gnuplot input file to get the real non-bonded interaction 
                  energy matrix

    gnuplot2.inp  gnuplot input file to get the symbolized non-bonded 
                  interaction energy matrix
