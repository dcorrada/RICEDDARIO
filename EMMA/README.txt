********************************************************************************
EMMA - Empathy Motions along fluctuation MAtrix
release 14.4.lbpc7

Copyright (c) 2011-2014, Dario CORRADA <dario.corrada@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

SOFTWARE REQUIREMENTS

    - GROMACS v4.0.7 or higher
    - GnuPlot 4.4.4 or higher
    - R v2.10.0 or higher
    - R packages: "cluster"; "clValid"; "RColorBrewer"; "RankAggreg"
    - Perl packages: "Statistics::Descriptive"; "Memory::Usage"

INSTALLATION

    Copy EMMA folder in you preferred installation path [...] and edit your
    bashrc file as follows:

        export PATH=[...]/EMMA/EMMA/bin:[...]/EMMA/RAGE/bin:$PATH
        export PERL5LIB=[...]/EMMA:$PERL5LIB

    At first time EMMA will create the file "/home/user/.EMMA.conf", in which 
    are stored the paths of third party softwares.
    
    In order to learn how to use EMMA:
    
        $ EMMA.reloaded.pl -h
