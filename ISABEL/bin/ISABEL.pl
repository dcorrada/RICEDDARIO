#!/usr/bin/perl
# -d

use strict;
use warnings;

## LIBS ##
use Data::Dumper; # show structured data (arrayy and hashes) in a hierarchical fashion 
use Cwd; # finding current work directory
use Carp; # aliases for 'warn' and 'die' commands with traceback
use File::Copy; # copying files
use ISABEL::lib::FileIO; # my lib for I/O functions over files
## SBIL ##

## GLOBS ##
my $workdir = getcwd(); # the current work directory
my $res_range = [ ]; # residue range onto performing calculations
my $refpdb; # reference structure file
my $snob; # I/O switch for bypassing Genoni's domain finder algorithm
my $file_obj = ISABEL::lib::FileIO->new(); # generic object for manipulating files
## SBLOG ##

## PATHS ##
my $ISA_path = qx/which ISABEL.pl/;
($ISA_path) = $ISA_path =~ /(.+)\/bin\/ISABEL\.pl$/;
my %address = (
    'leaprc_rc'     =>  $ISA_path . '/data/leaprc.ff03.v9', # con AMBER11 usare invece il file leaprc.ff03.v11
    'minin_rc'      =>  $ISA_path . '/data/min.in',
    'mmpbsain_rc'   =>  $ISA_path . '/data/mm_pbsa.in',
    'tleap_bin'     =>  '/usr/local/amber9/exe/tleap',
    'sander_bin'    =>  '/usr/local/amber9/exe/sander',
    'mmpbsa_bin'    =>  '/usr/local/amber9/exe/mm_pbsa.pl',
    'diagoxxl_bin'  =>  $ISA_path . '/bin/diagoxxl',
    'blocks_bin'    =>  $ISA_path . '/bin/blocks',
    'gnuplot_bin'   =>  '/home/student/opt/gnuplot44',
);
my $ISA_log = '/ISABEL.log';
## SHTAP ##

USAGE: {
    print "\n*** ISABEL ***\n";
    
    my $help;
    use Getopt::Long;no warnings;
    GetOptions('help|h' => \$help, 'path|p=s' => \$workdir, 'range|r=i{2}' => $res_range, 'snob|s' => \$snob);
    my $usage = <<END

********************************************************************************
ISABEL - ISabel is Another BEppe Layer
release 14.4.mazinga

Copyright (c) 2011-2014, Dario Corrada <dario.corrada\@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
*******************************************************************************

ISABEL is an AMBER tools wrapper that launch MM-GBSA calculations from a 
protein pdb file.

Then, for a specific range of residues (-r option) it perform Energy 
Decomposition analysis, taking into account the most representative eigenvectors 
from the diagonalized interaction energy matrix [1].

The interaction energy matrix values include the energy terms derived from 
solvation energy and pairwise electrostatic and van der Waals interactions. 
Intramolecular type 1-4 interaction are excluded from the calculation.

[1] Genoni A, Morra G, Colombo G. J Phys Chem B. 2012 Mar 15;116(10):3331-43

SYNOPSIS
    
    \$ ISABEL.pl [-p /destpath] [-r 5 20] [-s]

OPTIONS
    
    -path|p         working dir, in such path the reference pdb file must be 
                    included (default: pwd)
    
    -range|r        range of residues by which interaction energy matrix will be 
                    calculated (default: whole pdb structure)
    
    -snob|s         approximated energy matrix will be calculated only adopting 
                    the first eigenvector

RELEASE NOTES
    
    *** release 14.4.mazinga ***
    
    - Bugfix
        PDB re-format directives for AMBER software (see code lines below the 
        tag "# *** BUGFIX 14.4.mazinga - BEGIN ***")
    
    *** release 14.3.mazinga ***
    
    - First official release
END
    ;
    
    $help and do { print $usage; goto FINE; }
}

INIT: {

    # "mise en place" of the required files
    foreach my $check (keys %address) {
        croak("\nE- file [$address{$check}] not found\n\t") unless (-e $address{$check});
    };
    
    
    # reference structure check
    $file_obj->set_workdir($workdir);
    my $results = $file_obj->search_files('pattern' => '\.pdb$');
    $refpdb = shift @{$results};
    unless ($refpdb) {
        croak "\nE- no reference pdb file found\n\t";
    }
    $refpdb = $workdir . '/' . $refpdb;
    
    # workdir check
    croak "\nE- path [$workdir] not found\n\t" unless (-d $workdir);
    chdir $workdir;
    $workdir = getcwd();
    my $folder = $workdir . '/ISABEL';
    if (-e $folder) {
        my @info = stat($folder);
        my $mtime = $info[9];
        system("mv $folder $folder.$mtime");
    }
    mkdir $folder;
    
    # sorting residue range
    @{$res_range} = sort { $a <=> $b } @{$res_range};
    
    # defining destination path
    $workdir = $folder;
    chdir $workdir;
    
    # LOG file
    $ISA_log = $workdir . $ISA_log;
    $file_obj->set_filename($ISA_log);
    $file_obj->write('filedata' => [ "ISABEL log file"]);
}

AMBERPDB: {
    printf("\nI- %s converting pdb format for AMBER...\n", clock());
    
    $file_obj->set_filename($ISA_log);
    $file_obj->write('mode' => '>>', 'filedata' => [ "\n\n*** AMBER PDB CONVERSION", clock() ]);
    
    my $in_file = ISABEL::lib::FileIO->new('filename' => $refpdb);
    my $out_file = ISABEL::lib::FileIO->new('filename' => $workdir . '/snapshot.AMBER.pdb');
    
    my $in_content = $in_file->read();
    
    # importing the original reference structure
    my $pdb_content = [ ];
    while (my $newline = shift @{$in_content}) {
        chomp $newline;
        if ($newline !~ /^ATOM/) {
            next;
        }
        
        # parsing the "ATOM" records
        my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
        # the components of interest are:
        #   [1]     Atom serial number
        #   [3]     Atom name
        #   [4]     Alternate location indicator
        #   [5]     Residue name
        #   [7]     Chain identifier
        #   [8]     Residue sequence number
        #   [9]     Code for insertion of residues
        #   [11-13] XYZ coordinates
        #   [14]    Occupancy volume
        #   [15]    T-factor
        push(@{$pdb_content}, [ @splitted ]);
    }
    
    # pre-processing of the original pdb file
    my @Nterms;
    my @Cterms;
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        if ($pdb_content->[$i][3] =~ /\sN\s{2}/) { # finding N-term residues
            if ($pdb_content->[$i+1][3] =~ /\sH1\s{1}/) {
                push(@Nterms, $pdb_content->[$i][7].$pdb_content->[$i][8]); # bring chain+resID 
            }
        } elsif ($pdb_content->[$i][3] =~ /\sC\s{2}/) { # finding C-term residues
            if ($pdb_content->[$i+1][3] =~ /\s(O1 |OC1|O2 |OC2)/) {
                push(@Cterms, $pdb_content->[$i][7].$pdb_content->[$i][8]);
            }
        }
    }
    
    
    # histidine fix
    my %histidine_list;
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        if ($pdb_content->[$i][5] =~ /^HIS$/) {
            my $id_tag = $pdb_content->[$i][5] . $pdb_content->[$i][7] . $pdb_content->[$i][8];
            $histidine_list{$id_tag} = ' ' unless (exists $histidine_list{$id_tag});
            if ($pdb_content->[$i][3] =~ /HD1/) {
                $histidine_list{$id_tag} .= 'HD1';
            } elsif ($pdb_content->[$i][3] =~ /HE2/) {
                $histidine_list{$id_tag} .= 'HE2';
            }
        }
    }
    
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        if ($pdb_content->[$i][5] =~ /^HIS$/) {
            my $id_tag = $pdb_content->[$i][5] . $pdb_content->[$i][7] . $pdb_content->[$i][8];
            if (exists $histidine_list{$id_tag}) {
                if ($histidine_list{$id_tag} =~ /HD1HE2/) {
                    $pdb_content->[$i][5] = 'HIP';
                } elsif ($histidine_list{$id_tag} =~ /HE2/) {
                    $pdb_content->[$i][5] = 'HIE';
                } else {
                    $pdb_content->[$i][5] = 'HID';
                }
            }
        }
    }
    
    # isoleucine fix
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        if ($pdb_content->[$i][5] =~ /^ILE$/ && $pdb_content->[$i][3] =~ /^ CD $/) {
            $pdb_content->[$i][3] = ' CD1';
        }
    }
    
    # bringing info about sulfur atoms
    my $SG = [ ];
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        if ($pdb_content->[$i][5] =~ /^CYS$/ && $pdb_content->[$i][3] =~ /^ SG $/) {
            push(@{$SG}, $pdb_content->[$i]);
        }
    }
    
    # checking disulfides
    my %bridge;
    for (my $i = 0; $i < scalar @{$SG}; $i++) {
        for (my $j = $i + 1; $j < scalar @{$SG}; $j++) {
            my $xa = $SG->[$i][11]; $xa =~ s/\s//g; my $xb = $SG->[$j][11]; $xb =~ s/\s//g;
            my $ya = $SG->[$i][12]; $ya =~ s/\s//g; my $yb = $SG->[$j][12]; $yb =~ s/\s//g;
            my $za = $SG->[$i][13]; $za =~ s/\s//g; my $zb = $SG->[$j][13]; $zb =~ s/\s//g;
            my $distance = ($xa - $xb)**2 + ($ya - $yb)**2 + ($za - $zb)**2;
            $distance = sqrt $distance;
            if ($distance < 2.1) {
                my $key1 = $SG->[$i][7].$SG->[$i][8];
                my $key2 = $SG->[$i][7].$SG->[$i][8];
                $bridge{$key1} = 1 unless (exists $bridge{$key1});
                $bridge{$key2} = 1 unless (exists $bridge{$key2});
            }
        }
    }
    
    # cysteine fix
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        my $pattern = $pdb_content->[$i][7].$pdb_content->[$i]->[8];
        if (exists $bridge{$pattern}) {
            $pdb_content->[$i][5] = 'CYX';
        }
    }
    
    # C-term fix
    for (my $i = 0; $i < scalar @{$pdb_content}; $i++) {
        my $pattern = $pdb_content->[$i][7].$pdb_content->[$i]->[8];
        foreach my $ref (@Cterms) {
            if ($pattern =~ /$ref/ && $pdb_content->[$i][3] =~ /^ (O1 |OC1)$/) {
                $pdb_content->[$i][3] = ' O  ';
            } elsif ($pattern =~ /$ref/ && $pdb_content->[$i][3] =~ /^ (O2 |OC2)$/) {
                $pdb_content->[$i][3] = ' OXT';
            }
        }
    }
    
    # hydrogens remove
    my $pdb_noH = [ ];
    while (my $newline = shift @{$pdb_content}) {
        if ($newline->[3] =~ /^H/ ) {
            next;
        } elsif ($newline->[3] =~ /^.H/ ) {
            next;
        } else {
            push(@{$pdb_noH}, $newline);
        }
    }
    
    # *** BUGFIX 14.4.mazinga - BEGIN ***
    #
    # 04/04/2014 - Dario Corrada
    # Riformattazione del PDB. Il nuovo file risistemato per AMBER avra' atom
    # number, residue number e chain ID riordinati in modo progressivo. Inoltre
    # vengono aggiunti nuovi flag TER.
    #
    
    my @letters = ('A'..'Z');
    my $inc_chain = shift @letters;
    my ($inc_atom, $inc_resi) = (1, 1);
    my $current_chain = $pdb_noH->[0][7];
    my $current_res = $pdb_noH->[0][8];
    my ($prev_resn, $prev_ins);
    my $pdb_sorted = [ ];
    my @deepcopy;
    foreach my $newline (@{$pdb_noH}) {
        # faccio una deep copy dell'array giusto per non fare confusione
        @deepcopy = @{$newline}; 
        
        # aggiorno il residue number
        my $newer_res = $newline->[8];
        unless ($newer_res eq $current_res) {
            $inc_resi++;
            $current_res = $newer_res;
        }
        
        # aggiorno la chain ID
        my $newer_chain = $newline->[7];
        unless ($newer_chain eq $current_chain) {
            
            # inserisco un TER
            my $TER = sprintf("TER   % 5d     % 4s %s% 4d%s", 
                $inc_atom, $prev_resn, $inc_chain, $inc_resi-1, $prev_ins);
            
            $inc_atom++;
            $inc_chain = shift @letters;
            $current_chain = $newer_chain;
            push(@{$pdb_sorted}, $TER);
        }
        
        $deepcopy[1] = sprintf("% 5d",$inc_atom); # right justified format
        $deepcopy[8] = sprintf("% 4d",$inc_resi); # right justified format
        $deepcopy[7] = sprintf("%s",$inc_chain);
        
        push(@{$pdb_sorted}, join('', @deepcopy));
        ($prev_resn, $prev_ins) = ($deepcopy[5], $deepcopy[9]);
        
        $inc_atom++; # aggiorno l'atom number
    }
    my $TER = sprintf("TER   % 5d     % 4s %s% 4d%s", 
                $inc_atom, $prev_resn, $inc_chain, $inc_resi, $prev_ins);
    push(@{$pdb_sorted}, $TER);
    
    # writing processed pdb file
    my $out_content = [ "TITLE     ISABEL\n", "MODEL        1\n" ];
    while (my $newline = shift @{$pdb_sorted}) {
        push(@{$out_content}, $newline."\n");
    }
    push(@{$out_content}, "ENDMDL\n");
    $out_file->write('filedata' => $out_content);
    
    $file_obj->set_filename($ISA_log);
    $file_obj->write('mode' => '>>', 'filedata' => [ sprintf("\nI- file <%s> converted in AMBER format", $in_file->get_filename()) ]);
    
    # *** BUGFIX 14.4.mazinga - END ***
}


AMBERCONFIG: {
    printf("\nI- %s configuring AMBER input files...\n", clock());
    
    $file_obj->set_filename($ISA_log);
    $file_obj->write('mode' => '>>', 'filedata' => [ "\n\n*** AMBER SETUP ", clock() ]);
    
    $refpdb = $workdir . '/snapshot.AMBER.pdb';
    
    my $content;
    
    # editing <leaprc.ff03> from template
    $file_obj->set_filename($address{'leaprc_rc'});
    $content = $file_obj->read();
    my $trailer = <<END
protein = loadpdb $refpdb
saveamberparm  protein prot.prmtop prot.inpcrd
quit
END
    ;
    push(@{$content}, $trailer);
    $file_obj->set_filename($workdir . "/leaprc.ff03");
    $file_obj->set_filedata($content);
    $file_obj->write();
    
    # total residues
    $file_obj->set_filename($refpdb);
    $content = $file_obj->read();
    my $res = { };
    while (my $newline = shift @{$content}) {
        chomp $newline;
        if ($newline !~ /^ATOM/) {
            next;
        }
        my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
        unless( exists $res->{$splitted[7].$splitted[8]}) {
            $res->{$splitted[7].$splitted[8]} = $splitted[7];
        }
    }
    my $tot_res = scalar keys %{$res};
    
    # editing <min.in> from template
    $file_obj->set_filename($address{'minin_rc'});
    $content = $file_obj->read();
    for(my $i = 0; $i < scalar @{$content}; $i++) {
        if ($content->[$i] =~ /^RES/) {
            $content->[$i] = "RES 1 $tot_res\n";
        }
    }
    $file_obj->set_filename($workdir . '/min.in');
    $file_obj->set_filedata($content);
    $file_obj->write();
    
    # editing <mm_pbsa.in> from template
    $file_obj->set_filename($address{'mmpbsain_rc'});
    $content = $file_obj->read();
    for(my $i = 0; $i < scalar @{$content}; $i++) {
        if ($content->[$i] =~ /^\w{6}\s+start-end/) {
            $content->[$i] =~ s/start-end/1-$tot_res/;
        }
    }
    $file_obj->set_filename($workdir . '/mm_pbsa.in');
    $file_obj->set_filedata($content);
    $file_obj->write();
    
    $file_obj->set_filename($ISA_log);
    $file_obj->write('mode' => '>>', 'filedata' => [ "\nI- AMBER config files imported" ]);
}

AMBERJOBS: {
    printf("\nI- launching AMBER components...\n");
    
    $file_obj->set_filename($ISA_log);
    
    printf("\t%s generating topology\n", clock());
    my $amberlog = qx/cd $workdir; $address{'tleap_bin'} -s -f leaprc.ff03 2>&1/;
    $file_obj->write( 'mode' => '>>', 'filedata' => [ "\n\n*** TOPOLOGY RUN",  clock(), "\n", $amberlog ] );
    
    printf("\t%s minimization\n", clock());
    $amberlog = qx/cd $workdir; $address{'sander_bin'} -O -i min.in -p prot.prmtop -c prot.inpcrd -r prot-min.restrt -o prot.mdout 2>&1/;
    $file_obj->write( 'mode' => '>>', 'filedata' => [ "\n\n*** MINIMIZATION RUN ",  clock(), "\n",  $amberlog ] );
    
    printf("\t%s MM-GBSA with energy decomposition\n", clock());
    copy($workdir.'/prot-min.restrt', $workdir.'/prot-min_rec.crd.1');
    $amberlog = qx/cd $workdir; $address{'mmpbsa_bin'} mm_pbsa.in 2>&1/;
    $file_obj->write( 'mode' => '>>', 'filedata' => [ "\n\n*** MM-GBSA RUN  ",  clock(), "\n", , $amberlog ] );
}

DIAGONALLEY: {
    printf("\nI- %s diagonalize energy matrix...\n", clock());
    
    $file_obj->set_filename($ISA_log);
    $file_obj->write('mode' => '>>', 'filedata' => [ "\n\n*** DIAGONALIZATION ", clock() ]);
    
    $file_obj->set_filename($workdir . '/prot-min_statistics.out');
    my $in_content = $file_obj->read();
    
    my $record = [ ];
    my $out_content = [ ];
    my $resnumber;
    while (my $newline = shift @{$in_content}) {
        chomp $newline;
        @{$record} = split(/\s+/, $newline);
        if (scalar @{$record} == 53) { # parsing only lines containing records
            push(@{$out_content}, sprintf("%4d  %4d  %10.3f\n", $record->[2] - 1, $record->[4] - 1, $record->[15]+$record->[21]+$record->[45]));
            $resnumber = $record->[4];
        }
    }
    
    $file_obj->set_filename($workdir . '/ele-vdw.dat');
    $file_obj->set_filedata($out_content);
    $file_obj->write();
    
    my $diagoxxl_log = qx/cd $workdir; $address{'diagoxxl_bin'} $workdir\/ele-vdw.dat $resnumber 2>&1/;
    $file_obj->set_filename($ISA_log);
    $file_obj->write( 'mode' => '>>', 'filedata' => [ $diagoxxl_log ] );
}

AUTOMAN: {
    printf("\nI- %s energy eigendecomposition...\n", clock());
    
    $file_obj->set_filename($ISA_log);
    $file_obj->write('mode' => '>>', 'filedata' => [ "\n\n*** EIGEN DECOMPOSITION ", clock() ]);
    
    my $eigenvalues = [ ];
    my $eigenvectors = [ ];
    IMPORT: {
        my $newline;
        $file_obj->set_filename($workdir . '/EIGENVAL.txt');
        my $content = $file_obj->read();
        while ($newline = shift @{$content}) {
            chomp $newline;
            push(@{$eigenvalues}, $newline);
        }
        $file_obj->set_filename($workdir . '/EIGENVECT.txt');
        $content = $file_obj->read();
        while ($newline = shift @{$content}) {
            chomp $newline;
            my @record = split (/\s+/, $newline);
            push(@{$eigenvectors}, [ @record ]); 
        }
    }
    
    my $resnumber = scalar @$eigenvectors;
    my @quali;
    
    ($snob) and do { 
        @quali = ( '0' );
        $file_obj->set_filename($ISA_log);
        $file_obj->write('mode' => '>>', 'filedata' => [ "\nW- <FORECAST> block skipped, selecting the first eigenvector\n" ]);
        goto DISTRIB;
    };
    
    FORECAST: { # how many eigenvectors calculation needs?
        $file_obj->set_filename($workdir . '/fort.35'); # in the context of Genoni's software <fort.35> is a contact map for further cluster optimization; since I don't need clustering, I will create a fake one
        my $content = [ ]; my $newline;
        for (my $i = 1; $i <= $resnumber; $i++) {
            for (my $j = 1; $j <= $resnumber; $j++) {
                if ($i == $j) {
                    $newline = "$i $j 1\n";
                } else {
                    $newline = "$i $j 0\n";
                }
                push(@{$content}, $newline);
            }
            push(@{$content}, "\n");
        }
        $file_obj->set_filedata($content);
        $file_obj->write();
        my $cmd = <<FIN
cd $workdir;
ln -s ./EIGENVECT.txt fort.30;
ln -s ./EIGENVAL.txt fort.31;
touch fort.32;
touch fort.33;
touch fort.34;
echo '\$PARAMS  NRES=$resnumber FRACT=0.6d0 TOTAL=.TRUE. NTM=3 PERCOMP=0.5 NGRAIN=5 LENGTH=50 \$END' | $address{'blocks_bin'} 2> blocks.error;
mv fort.32 SELECTED_EIGENVECTORS.txt;
mv fort.33 energy.txt;
mv fort.34 energy_blocks1.txt;
rm -rfv fort.*;
FIN
        ;
        my $blocks_log = qx/$cmd/;
        my ($match_string) = $blocks_log =~ m/ESSENTIAL CLUSTER OF EIGENVECTORS:\s+([\s\d]+)\n/m;
        $file_obj->set_filename($ISA_log);
        $file_obj->write('mode' => '>>', 'filedata' => [ "\n", $blocks_log ]);
        unless ($match_string) {
            croak("\nE- eigendecomposition error, please see ISABEL.log\n\t");
        }
        @quali = split(/\s+/, $match_string);
        @quali = map { $_-1 } @quali;
        
        $file_obj->set_filename($ISA_log);
        $file_obj->write('mode' => '>>', 'filedata' => [ sprintf("\n*** SELECTED EIGENS [ %s ]\n", join(' ',sort {$a <=> $b} @quali)) ]);
    }
    
    DISTRIB: {
        my $threshold = sqrt ( 1 / $resnumber); # threshold value for highlight hotspots
        # @components is composed by the maximum values hosted by the selected eigenvectors
        my @components = split(':', "0:" x $resnumber); # initializing
        foreach my $av (@quali) {
            for (my $i = 0; $i < $resnumber; $i++) {
                $components[$i] = abs($eigenvectors->[$i][$av])
                    if (abs($eigenvectors->[$i][$av]) > abs($components[$i]));
            }
        }
        my $profile = [ ]; my $i = 1;
        foreach my $value (@components) {
            push(@{$profile}, sprintf("%d  %.6f\n", $i, $value));
            $i++;
        }
        
        $file_obj->set_filename($workdir . '/enedist.dat');
        $file_obj->set_filedata($profile);
        $file_obj->write();
    }
    
    ENEMATRIX: {
        # initializing
        my @enematrix;
        foreach (my $i = 0; $i < $resnumber; $i++) {
            foreach (my $j = 0; $j < $resnumber; $j++) {
                $enematrix[$i][$j] = 0E0;
            }
        }
        
        foreach my $automan (@quali) {
            foreach (my $i = 0; $i < $resnumber; $i++) {
                foreach (my $j = 0; $j < $resnumber; $j++) {
                    my $value = $eigenvalues->[$automan] * $eigenvectors->[$i][$automan] * $eigenvectors->[$j][$automan];
                    $enematrix[$i][$j] += $value;
                }
            }
        }
        
        my $content = [ ];
        foreach (my $i = 0; $i < $resnumber; $i++) {
            foreach (my $j = 0; $j < $resnumber; $j++) {
                push(@{$content}, sprintf("%d  %d  %.6f\n", $i+1, $j+1, $enematrix[$i][$j]));
            }
            push(@{$content}, "\n");
        }
        
        $file_obj->set_filename($workdir . '/enematrix.dat');
        $file_obj->set_filedata($content);
        $file_obj->write();
    }
}

PLOTS: {
    printf("\nI- %s generating graphics...\n", clock());
    
    $file_obj->set_filename($ISA_log);
    $file_obj->write('mode' => '>>', 'filedata' => [ "\n\n*** PLOTTING ", clock() ]);
    
    unless (defined $res_range->[1]) {
        $res_range->[0] = 1;
        my $log = qx/wc -l $workdir\/enedist.dat/;
        ($res_range->[1]) = $log =~ /^(\d+)/;
    }
    
    PROFILO: {
        $file_obj->set_filename($workdir . '/enedist.dat');
        my $content = $file_obj->read();
        my @components;
        while (my $newline = shift @{$content}) {
            chomp $newline;
            next unless $newline;
            my ($res, $value) = $newline =~ /(\d+)\s+([\-\.\d]+)/;
            push(@components, $value);
        }
        my $threshold = sqrt ( 1 / scalar @components); 
        
        # separating values above or below threshold
        $file_obj->set_filename($workdir . '/down');
        my $down = [ ]; my $i = 1;
        foreach my $value (@components) {
            my $eval = $value;
            $eval = 0E0 if (abs($eval) > $threshold);
            push(@{$down}, sprintf("%d  %.6f\n", $i, $eval));
            $i++;
        }
        $file_obj->set_filedata($down);
        $file_obj->write();
        $file_obj->set_filename($workdir . '/up');
        my $up = [ ]; $i = 1;
        foreach my $value (@components) {
            my $eval = $value;
            $eval = 0E0 if (abs($eval) < $threshold);
            push(@{$up}, sprintf("%d  %.6f\n", $i, $eval));
            $i++;
        }
        $file_obj->set_filedata($up);
        $file_obj->write();
        
        my $max = 0E0; my $min = 0E0;
        foreach my $value (@components) {
            $max = $value if ($value > $max);
            $min = $value if ($value < $min);
        }
        
        my $gnuscript = <<END
# 
# *** ISABEL - ISabel is Another BEppe Layer ***
#
# Gnuplot script to draw energy distribution
# 
set terminal png size 2400, 800
set size ratio 0.33
set output "enedist.png"
set key
set tics out
set xrange[$res_range->[0]:$res_range->[1]]
set xtics rotate
set xtics nomirror
set xtics 10
set mxtics 10
set xlabel "resID"
set yrange [$min:$max+0.1]
set ytics 0.1
set mytics 10
plot    "up" with impulses lw 3 lt 1, \\
        "down" with impulses lw 3 lt 9
END
        ;
        $file_obj->set_filename($workdir . '/enedist.gnuplot');
        $file_obj->set_filedata([ $gnuscript ]);
        $file_obj->write();
        
        #  .png file
        my $gplot_log = qx/cd $workdir; $address{'gnuplot_bin'} enedist.gnuplot 2>&1/;
        $file_obj->set_filename($ISA_log);
        $file_obj->write( 'mode' => '>>', 'filedata' => [ "\n", $gplot_log ]);
        unlink ( $workdir . '/down', $workdir . '/up');
    }
    
    MATRICE: {
        $file_obj->set_filename($workdir . '/enematrix.dat');
        my $content = $file_obj->read();
        my $ave = 0E0; my $counter = 0E0;
        while (my $row = shift @{$content}) {
            chomp $row;
            next unless $row;
            my ($r1,$r2,$value) = split(/\s+/, $row);
            if ($value < 0) {
                $ave += $value;
                $counter++;
            }
        }
        $ave = $ave / $counter;
        
        my $gnuscript = <<END
# 
# *** ISABEL - ISabel is Another BEppe Layer ***
#
# Gnuplot script to draw energy matrix
# 
set terminal png size 2400, 2400
set output "enematrix.png"
set size square
set pm3d map
set palette rgbformulae 34,35,36
set cbrange[$ave-0.5 to $ave]
set tics out
set xrange[$res_range->[0]:$res_range->[1]]
set yrange[$res_range->[0]:$res_range->[1]]
set xtics 10
set xtics rotate
set ytics 10
set mxtics 10
set mytics 10
splot "enematrix.dat"
END
        ;
        $file_obj->set_filename($workdir . '/enematrix.gnuplot');
        $file_obj->set_filedata([ $gnuscript ]);
        $file_obj->write();
        
        #  .png file
        my $gplot_log = qx/cd $workdir; $address{'gnuplot_bin'} enematrix.gnuplot 2>&1/;
        $file_obj->set_filename($ISA_log);
        $file_obj->write( 'mode' => '>>', 'filedata' => [ "\n",  $gplot_log ]);
    }
}

SUMMA: {
    printf("\nI- %s calculating total energy...\n", clock());
    
    my %partners;
    foreach my $res ($res_range->[0]..$res_range->[1]) {
        $partners{$res} = 1;
    }
    
    $file_obj->set_filename($workdir . '/enematrix.dat');
    my $content = $file_obj->read();

    # summing energy contributions
    my $enesum = 0E0;
    while (my $row = shift @{$content}) {
        chomp $row;
        my ($p1,$p2,$ene) = $row =~ m/(\d+)\s+(\d+)\s+([\d\-eE\.]+)/;
        next unless $ene;
        next if ($p1 == $p2); # don't care about type 1-4 contributions
        if ((exists $partners{$p1}) && (exists $partners{$p2})) {
            $enesum += $ene;
        } else {
            next;
        }
    }

    my $results = sprintf("\n\n*** TOTAL ENERGY %.3f kJ/mol\n", $enesum * 4.184);
    $file_obj->set_filename($ISA_log);
    $file_obj->write( 'mode' => '>>', 'filedata' => [ $results ] );
}

CLEANSWEEP: {
    printf("\nI- %s cleaning temporary files...", clock());
    unlink $workdir . '/blocks.error';
    unlink $workdir . '/ele-vdw.dat';
    unlink $workdir . '/enedist.gnuplot';
    unlink $workdir . '/enematrix.gnuplot';
    unlink $workdir . '/energy.txt'; 
    unlink $workdir . '/energy_blocks1.txt';
    unlink $workdir . '/leap.log';
    unlink $workdir . '/leaprc.ff03';
    unlink $workdir . '/matrice'; # raw energy matrix
    unlink $workdir . '/mdinfo';
    unlink $workdir . '/min.in';
    unlink $workdir . '/mm_pbsa.in';
    unlink $workdir . '/prot.inpcrd';
    unlink $workdir . '/prot.mdout';
    unlink $workdir . '/prot-min.restrt';
    unlink $workdir . '/prot-min_rec.crd.1';
    unlink $workdir . '/prot-min_rec.all.out';
    unlink $workdir . '/prot-min_statistics.in';
    unlink $workdir . '/SELECTED_EIGENVECTORS.txt';
}

FINE: {
    print "\n*** LEBASI ***\n";
    exit;
}

sub clock {
    my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
    $mese = $mese+1;
    $mese = sprintf("%02d", $mese);
    $giom = sprintf("%02d", $giom);
    $ore = sprintf("%02d", $ore);
    $min = sprintf("%02d", $min);
    $sec = sprintf("%02d", $sec);
    my $date = '[' . ($anno+1900)."/$mese/$giom $ore:$min:$sec]";
    return $date;
}
