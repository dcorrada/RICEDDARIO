#!/usr/bin/perl
# -d

use strict;
use warnings;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| = 1;

# paths di librerie personali
use lib $ENV{HOME};

# il metodo Dumper restituisce una stringa (con ritorni a capo \n)
# contenente la struttura dati dell'oggetto in esame.
#
# Esempio:
#   $obj = Class->new();
#   print Dumper($obj);
use Data::Dumper;

################################################################################
# PREMESSA - quando ho allestito il mio dataset mi sono imposto alcune regole 
# generali del tipo:
# 1. La costruzione del box solvatato e i relativi file li metto in una cartella 
# chiamata "allestimento"
# 2. La minimizzazione e i relativi file li metto in una cartella 
# chiamata "minimizzazione"
# 3. La dinamica e i relativi file li metto in una cartella chiamata 
# "simulazione"
# 
# Questo script si occupa di:
# 
# (a) Cercare, a partire da un percorso definito (pwd di default), quei path in 
# cui è necessario allestire i file necessari per far partire una simulazione.
# 
# (b) Per ogni path trovato in (a) crea una cartella "simulazione" in cui copia 
# dentro tutti i file necessari.
# 
# (c) Legge il file "topo.top" e apporta le necessarie modifiche al file .mdp 
# (es. il nome delle specie ioniche "NA+" o "CL-")


use Cwd;
use Carp;
use RICEDDARIO::lib::FileIO;
use File::Copy;
use File::Spec::Unix;

#######################
## VARIABILI GLOBALI ##
our $search_path = getcwd();
our $mdp_file = $ENV{HOME} . '/GOLEM_RAWDATA/tools/20ns_NPT.mdp'; # a mdp file
our $top_file = 'topol.top';
our $gro_file = 'conf.em.gro'; # uso il gro post-minimizzazione
our %targets; # hash con i dati dei path da inizializzare
our $GMX = '/usr/local/GMX407/bin/GMXRC'; # Gromacs source script
#######################

CHECK_MDP: {
    croak("E- [$mdp_file] not found...\n\t")
        if (! -e $mdp_file);
}

SEARCH_PATHS: {
    # cerco i path da inizializzare e aggiorno l'hash %targets
    
    if ($ARGV[0]) { # specifico il percorso in cui cercare i paths
        my $new_path = $ARGV[0];
        if (-d $new_path) {
            chdir $new_path;
            $search_path = getcwd();
        } else {
            print "\nW- path [$new_path] not found";
            print "\n-- would search trough [$search_path](Y/n)? ";
            my $answer = <STDIN>;
            if ($answer and $answer =~ m/(n|no)/i) {
                print "\n-- aborting $0\n\t";
                goto FINE;
            }; 
        }
    }
    print "\n-- searching through [$search_path]...";
    
    # lista di paths da inizializzare
    my $obj = RICEDDARIO::lib::FileIO->new();
    my $paths_list = $obj->search_dir('pattern' => $search_path);
    
    
    foreach my $path (keys %{$paths_list}) {
        chdir $paths_list->{$path};
        if (-d 'simulazione') { # cerco le cartelle in cui sono gia' presenti le simulazioni e le scarto dalla lista
            chdir 'simulazione';
            if (@{$obj->search_files('pattern' => '.tpr$')}) {
                printf("\nW- [%s] already contains simulation data, path skipped", $paths_list->{$path});
                delete $paths_list->{$path};
                next;
            }
        }
        $targets{$path} = { };
        $targets{$path}->{'path'} = $paths_list->{$path};
    }
}


SEARCH_FILES: {
    # cerco i files necessari nei path da inizializzare aggiorno l'hash %targets
    
    foreach my $record (keys %targets) {
        my $path = $targets{$record}->{'path'};
        $targets{$record}->{'files'} = [ ];
        
        chdir $path;
        my $gro = getcwd() . '/minimizzazione/' . $gro_file; 
        my $top = getcwd() . '/allestimento/' . $top_file;
        
        # verifico che ci siano i file .gro e .top
        if  (! -e $gro) {
            print "\nW- [$gro_file] not found in [$path], path skipped";
            delete $targets{$record};
            next;
        } else {
            push(@{$targets{$record}->{'files'}}, $gro);
        }
        
        if (! -e $top) {
            print "\nW- [$top_file] not found in [$path], path skipped";
            delete $targets{$record};
            next;
        } else {
            push(@{$targets{$record}->{'files'}}, $top);
        }
        
        # verifico che ci siano tutti i file .itp associati al file topol.top
        chdir 'allestimento';
        my @itp_files;
        
        $/ = ';'; # uso ';' come separatore di campo per leggere i file topol.top
        my $obj = RICEDDARIO::lib::FileIO->new('filename'=>$top);
        my $content = $obj->read();
        $/ = "\n"; # ripristino l'input separator a default
        while (my $chain_tops = shift @{$content}) {
            if ($chain_tops =~ m/^ Include chain topologies/) {
                @itp_files = $chain_tops =~ m/"(\w+\.itp)"/g;
                last;
            }
        }
        
        chdir $path;
        my $itp_lost = 0;
        foreach my $itp_file (@itp_files) {
            my $itp = getcwd() . '/allestimento/' . $itp_file;
            if (! -e $itp) {
                print "\nW- [$itp_file] not found in [$path]";
                $itp_lost = 1;
            } else {
                push(@{$targets{$record}->{'files'}}, $itp);
            }
        }
        if ($itp_lost) {
            print ", path skipped";
            delete $targets{$record};
            next;
        }
    }
}

COPY_FILES: {
    # creo una cartella "simulazione" e copio li dentro i files
    
    foreach my $record (keys %targets) {
        my $workdir = $targets{$record}->{'path'} . 'simulazione';
        print "\n-- preparing [$workdir]...";
        mkdir $workdir;
        foreach my $abs_path (@{$targets{$record}->{'files'}}) {
            my ($volume,$source_dir,$file_name) = File::Spec->splitpath($abs_path);
            copy($abs_path, $workdir . '/' . $file_name) or croak("E- file [$abs_path] cannot be copied\n\t");
        }
        print "done";
    }
}


PARSE_TOPOL: {
    # faccio un parsing dei file topol.top e allestisco un file mdp di conseguenza
    
    foreach my $record (keys %targets) {
        my $workdir =  $targets{$record}->{'path'} . 'simulazione/';
        
        # cerco, le specie ioniche che sono state usate per neutralizzare la carica
        my $ions = '';
        $/ = ';'; # uso ';' come separatore di campo per leggere i file topol.top
        my $top_obj = RICEDDARIO::lib::FileIO->new('filename'=> $workdir . $top_file);
        my $top_content = $top_obj->read();
        $/ = "\n"; # ripristino l'input separator a default
        while (my $molecules = shift @{$top_content}) {
            if ($molecules =~ m/^ Compound        \#mols/) {
#                 print "\n---\n$record\n---\n";
#                 print $molecules;
                my ($sodium, $chlorine); # specie ioniche che considero
                if ($molecules =~ m/(NA\+|CL\-)/) {
                    ($sodium) = $molecules =~ m/NA\+\s+(\d+)\n/;
                    ($chlorine) = $molecules =~ m/CL\-\s+(\d+)\n/;
                    if ($sodium) {
                        print "\n-- system [$record] has $sodium NA+";
                        $ions = 'sodium';
                    } elsif ($chlorine) {
                        print "\n-- system [$record] has $chlorine CL-";
                        $ions = 'chlorine';
                    }
                } else {
                    print "\n-- system [$record] has no added ions";
                    $ions = 'none';
                }
                last;
            }
        }
        
        # modifico ad hoc il file mdp in base alla presenza di cariche
        print "\n-- creating mdp file...";
        my ($volume,$source_dir,$mdp_filename) = File::Spec->splitpath($mdp_file);
        
        # leggo il templato
        my $template_obj = RICEDDARIO::lib::FileIO->new('filename' => $mdp_file);
        my $mdp_content = $template_obj->read();
        
        
        $_ = $ions;
        SWITCH: {
            /sodium/ and do { # copio il file tale e quale, il template di default e' scritto con NA+ 
                copy($mdp_file, $workdir . $mdp_filename) or croak("E- file [$mdp_file] cannot be copied\n\t");
                push(@{$targets{$record}->{'files'}}, $workdir . $mdp_filename);
                print "done";
                last SWITCH;
            };
            /chlorine/ and do {
                my @mdp_patched;
                foreach my $row (@{$mdp_content}) {
                    $row =~ s/= Protein SOL NA\+/= Protein SOL CL\-/
                        if ($row =~ m/= Protein SOL NA\+/);
                    push(@mdp_patched, $row);
                }
                my $new_mdp = RICEDDARIO::lib::FileIO->new('filename' => $workdir . $mdp_filename, 'filedata' => \@mdp_patched);
                $new_mdp->write();
                push(@{$targets{$record}->{'files'}}, $workdir . $mdp_filename);
                print "done";
                last SWITCH;
            };
            /none/ and do {
                my @mdp_patched;
                foreach my $row (@{$mdp_content}) {
                    $row =~ s/= Protein SOL NA\+/= Protein SOL/
                        if ($row =~ m/= Protein SOL NA\+/);
                    $row =~ s/tau_t                    = 0.2 0.2 0.2/tau_t                    = 0.2 0.2/
                        if ($row =~ m/tau_t                    = 0.2 0.2 0.2/);
                    $row =~ s/ref_t                    = 300 300 300/ref_t                    = 300 300/
                        if ($row =~ m/ref_t                    = 300 300 300/);
                    $row =~ s/annealing                = no no no/annealing                = no no/
                        if ($row =~ m/annealing                = no no no/);
                    push(@mdp_patched, $row);
                }
                my $new_mdp = RICEDDARIO::lib::FileIO->new('filename' => $workdir . $mdp_filename, 'filedata' => \@mdp_patched);
                $new_mdp->write();
                push(@{$targets{$record}->{'files'}}, $workdir . $mdp_filename);
                print "done";
                last SWITCH;
            };
        }
    }
}

GROMPP: {
    # pre-processing della simulazione
    
    foreach my $record (keys %targets) {
        my $workdir =  $targets{$record}->{'path'} . 'simulazione/';
        
        print "\n-- pre-processing [$record]...";
        my $cmd_line = <<ENDCMD
source $GMX;
cd $workdir;
grompp -f 20ns_NPT.mdp -c conf.em.gro -p topol.top -o MD_20ns.tpr -maxwarn 3 >& grompp.log;
ENDCMD
        ;
        system($cmd_line);
        print "done";
    }
}

FINE: {
    print "\n---\nFINE PROGRAMMA\n";
    exit;
}
