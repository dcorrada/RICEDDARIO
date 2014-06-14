#!/bin/sh

# main paths
export PERL5LIB=$RICEDDARIOHOME:$PERL5LIB
export PATH=$RICEDDARIOHOME/job_scheduling:$RICEDDARIOHOME/Qlite:$RICEDDARIOHOME/sequence:$RICEDDARIOHOME/structure:$RICEDDARIOHOME/web_services:$RICEDDARIOHOME/WORKFLOW:$RICEDDARIOHOME/third_parties/AMBER:$RICEDDARIOHOME/third_parties/BLOCKS:$RICEDDARIOHOME/third_parties/BOWTIE:$RICEDDARIOHOME/third_parties/GROMACS:$RICEDDARIOHOME/third_parties/MAQ:$RICEDDARIOHOME/third_parties/MODELLER:$RICEDDARIOHOME/third_parties/PYMOL:$RICEDDARIOHOME/third_parties/VMD:$PATH

# EMMA
export PATH=$RICEDDARIOHOME/EMMA/EMMA/bin:$RICEDDARIOHOME/EMMA/RAGE/bin:$PATH
export PERL5LIB=$RICEDDARIOHOME/EMMA:$PERL5LIB


