package BRENDA::lib::Rambo;

use strict;
use warnings;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| =1;

use lib $ENV{HOME};

# il metodo Dumper restituisce una stringa (con ritorni a capo \n)
# contenente la struttura dati dell'oggetto in esame.
#
# Esempio:
#   $obj = Class->new();
#   print Dumper($obj);
use Data::Dumper;

###################################################################
# RAMBO - Routines AMBer Oriented

use Carp;
use File::Copy;
use base ( 'BRENDA::lib::Generic_class' ); # eredito la classe generica contenente il costruttore, l'AUTOLOAD ecc..
use base ( 'BRENDA::lib::FileIO' ); # eredito la classe per gestire le lettura/scrittura di file
our $AUTOLOAD;

# Definizione degli attributi della classe
# chiave        -> nome dell'attributo
# valore [0]    -> valore di default
# valore [1]    -> permessi di accesso all'attributo
#                  ('read.[write.[...]]')
# STRUTTURA DATI
our %_attribute_properties = (
    _logfile        => [ '/RAMBO.log', 'read.' ],
    
    # attributi specifici dei metodi
    _gmxsnapshot_opt    => [ {
    'xtc'           =>  '',
        'tpr'       =>  '',
        'frame'     =>  '',
        'workdir'   =>  ''
    }, 'read.write.' ],
    _mmpbsa_opt         => [ {
        'receptor'  => '',
        'ligand'    => '',
        'complex'   => ''
    }, 'read.write.' ],
    _parser_opt         => [ { }, 'read.write.' ],
    
    # binaries
    _tleap              => [ '/usr/local/Amber_11/amber11/exe/tleap', 'read.' ],
    _sander             => [ '/usr/local/Amber_11/amber11/exe/sander', 'read.' ],
    _mmpbsa             => [ '/usr/local/Amber_11/amber11/exe/mm_pbsa.pl', 'read.' ],
    _trjconv            => [ '/usr/local/GMX407/bin/trjconv', 'read.']
);

# Unisco gli attributi della classi madri con questa
my $ref = BRENDA::lib::Generic_class::_hash_joiner(\%BRENDA::lib::Generic_class::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = BRENDA::lib::Generic_class::_hash_joiner(\%BRENDA::lib::FileIO::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;

# COSTRUTTORE
sub new {
    my ($class, %arg) = @_;

    # crea un nuovo oggetto
    my $self = bless { }, $class;
    # inizializza gli attributi dell'oggetto...
    foreach my $attribute ($self->_all_attributes()) {
        $attribute =~ m/^_(\w+)$/;
        # ...con il valore passato in argomento...
        if (exists $arg{$1}) {
            # (verifica dei privilegi in scrittura per l'attributo)
            if ($self->_permissions($attribute, 'write')) {
                $self->{$attribute} = $arg{$1};
            } else {
                print "\nW- Attributo $attribute disponibile in sola lettura\n";
                $self->{$attribute} = $self->_attribute_default($attribute);
            }
        # ...o con il valore di default altrimenti
        } else {
            $self->{$attribute} = $self->_attribute_default($attribute);
        }
    }

    # verifico se sono stati chiamati degli attributi che non sono previsti in questa classe
    $self->_check_attributes(keys %arg);
    
    # verifico se sono istallati i programmi usati da questa libreria
    foreach my $file ( $self->get_tleap(), $self->get_sander(), $self->get_mmpbsa(), $self->get_trjconv() ) {
        unless (-e $file) {
            $self->_raise_warning("\nE- file [$file] not found\n\n");
            return 1;
        }
    }
    
    return $self;
}

sub parser {
# raccolgo gli output prodotti da mm_pbsa.pl in un unico file
    my ($self) = @_;
    my $opt = $self->get_parser_opt();
    my $out_file = $self->get_workdir . '/BRENDA_energy.csv';
    
    $self->write(
        'filename'  => $out_file,
        'filedata'  => [ "SYSTEM;ELE_r;VDW_r;ASA_r;ELE_l;VDW_l;ASA_l;ELE_c;VDW_c;ASA_c\n" ]
    );
    
    foreach my $id (keys %{$opt}) {
        my %files = (
            'rec' => $opt->{$id} . '/BRENDA/MM-GBSA/prot-min_rec.all.out',
            'lig' => $opt->{$id} . '/BRENDA/MM-GBSA/prot-min_lig.all.out',
            'com' => $opt->{$id} . '/BRENDA/MM-GBSA/prot-min_com.all.out',
        );
        my $data = { 'rec' => [ ], 'lig' => [ ], 'com' => [ ] };
        
        foreach my $mmpbsa_out (keys %files) {
            unless (-e $files{$mmpbsa_out}) {
                $self->_raise_warning("\nE- file [$files{$mmpbsa_out}] not found\n\n");
                return 1;
            }
            my $record = [ ];
            my $content = $self->read($files{$mmpbsa_out});
            
            while (my $newline = shift @{$content}) {
                chomp $newline;
                $newline =~ /^ VDWAALS =/ && do {
                    my ($vdw,$ele) = $newline =~ /^ VDWAALS =\s+([\d\.\-]+)\s+EEL     =\s+([\d\.\-]+)/;
                    $record = [ $ele, $vdw ];
                };
                $newline =~ /^surface area =/ && do {
                    my ($sur) = $newline =~ /^surface area =\s+([\d\.\-]+)/;
                    push(@{$record}, $sur);
                    push(@{$data->{$mmpbsa_out}}, $record);
                };
            }
        }
        
        my $row = "$id;";
        for (my $count = 0E0; $count < scalar @{$data->{'rec'}}; $count++) {
            my $receptor = join(';', @{$data->{'rec'}->[$count]});
            my $ligand = join(';', @{$data->{'lig'}->[$count]});
            my $complex = join(';', @{$data->{'com'}->[$count]});
            my $string = sprintf("%s;%s;%s\n", $receptor, $ligand, $complex);
            $self->write(
                'mode'      => '>>',
                'filename'  => $out_file,
                'filedata'  => [ $row . $string ]
            );
        }
        
    }
}

sub gbsa {
# lancio MM-GBSA
    my ($self) = @_;
    my $opt = $self->get_mmpbsa_opt();
    $self->set_workdir($opt->{'complex'} . '/BRENDA/MM-GBSA');
    
    # creo la directory di lavoro
    mkdir $self->get_workdir();
    
    # copio i file di input
    my %abbrev = ( 'receptor'  => 'rec', 'ligand'    => 'lig', 'complex'   => 'com' );
    foreach my $whatta (keys %{$opt}) {
        my $prmtop = $self->get_workdir() . '/' . $abbrev{$whatta} . '.prmtop';
        my $crd_prefix = $self->get_workdir() . '/prot-min_' . $abbrev{$whatta} . '.crd.';
        my $path = $opt->{$whatta} . '/BRENDA';
        opendir(DIR, $path);
        my @snaps = grep { /^\d+$/ && -d "$path/$_" } readdir(DIR);
        closedir DIR;
        my $count = 0E0;
        while (my $snap = shift @snaps) {
            $count++;
            my $crd = $crd_prefix . $count;
            my @originals = (
                $path . '/' . $snap . '/prot.prmtop',
                $path . '/' . $snap . '/prot-min.restrt'
            );
            foreach my $check (@originals) {
                unless (-e $check) {
                    $self->_raise_warning("\nE- file [$check] not found\n\n");
                    return 1;
                }
            }
            # copio il file di topologia se non c'è
            copy($originals[0], $prmtop) unless (-e $prmtop);
            # copio il file di struttura dello snapshot
            copy($originals[1], $crd);
        }
    }
    
    # copio il file di configurazione
    my $mmpbsain_template = <<END
\@GENERAL
PREFIX                prot-min
PATH                  ./
COMPLEX               1
RECEPTOR              1
LIGAND                1
COMPT                 ./com.prmtop
RECPT                 ./rec.prmtop 
LIGPT                 ./lig.prmtop
GC                    0
AS                    0
DC                    0
MM                    1 
GB                    1
PB                    0
MS                    0
NM                    0

\@MM
DIELC                 1.0

\@GB
IGB                   2
GBSA                  2
SALTCON               0.00
EXTDIEL               80.0
INTDIEL               1.0
SURFTEN               0.0072
SURFOFF               0.00 
END
    ;
    $self->set_filename($self->get_workdir() . '/mmpbsa.in');
    $self->write('filedata' => [ $mmpbsain_template ]);
    
    # lancio mm_pbsa.pl
    my $dest_path = $self->get_workdir();
    my $mmpbsa = $self->get_mmpbsa();
    my $amberlog = qx/cd $dest_path; $mmpbsa mmpbsa.in 2>&1/;
    $self->set_filename($dest_path . $self->get_logfile());
    $self->write( 'mode' => '>>', 'filedata' => [ "\n\n*** MM-GBSA ***\n", $amberlog ] );
}

sub minimize {
# lancio le minimizzazioni
    my ($self) = @_;
    
    # check dei file di input
    my $pdb = $self->get_workdir . '/snapshot.AMBER.pdb';
    my $prmtop = $self->get_workdir . '/prot.prmtop';
    my $inpcrd = $self->get_workdir . '/prot.inpcrd';
    foreach my $check ($pdb, $prmtop, $inpcrd) {
        unless (-e $check) {
            $self->_raise_warning("\nE- file [$check] not found\n\n");
            return 1;
        }
    }
    
    # conto il numero di residui nel pdb di riferimento
    my $content = $self->read($pdb);
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
    
    # templato del file di configurazione
    my $minin_template = <<FIN
Test run 1
 &cntrl
   imin=1,
   maxcyc=200,
   cut=12.0,
   igb=2,
   saltcon=0.1,
   gbsa=1,
   ntpr=10,
   ntx=1,
   ntb=0
 /
ENERGY
Group 1
RES 1 $tot_res 
END
FIN
    ;
    
    $self->set_filename($self->get_workdir() . '/min.in');
    $self->write('filedata' => [ $minin_template ]);
    
    # lancio sander
    my $dest_path = $self->get_workdir();
    my $sander = $self->get_sander();
    my $amberlog = qx/cd $dest_path; $sander -O -i min.in -p prot.prmtop -c prot.inpcrd -r prot-min.restrt -o prot.mdout 2>&1/;
    $self->set_filename($dest_path . $self->get_logfile());
    $self->write( 'mode' => '>>', 'filedata' => [ "\n\n*** SANDER ***\n", $amberlog ] );
}

sub gmxsnapshot {
# campiona uno snapshot dalla traiettoria di GROMACS e converte il pdb x AMBER
    my ($self) = @_;
    my $opt = $self->get_gmxsnapshot_opt();
    $self->set_workdir($opt->{'workdir'});
    
    SAMPLING: { # campiono lo snapshot
        my $string = sprintf("echo 1 | %s -f %s -s %s -pbc nojump -dump %s -o %s/snapshot.GROMACS.pdb &> /dev/null", $self->get_trjconv(), $opt->{'xtc'}, $opt->{'tpr'}, $opt->{'frame'}, $self->get_workdir());
        system $string;
    }
    
    CONVERSION: { # converto il pdb x AMBER
        # leggo il file pdb generato da GROMACS
        my $in_content = $self->read($self->get_workdir() . '/snapshot.GROMACS.pdb');
        
        # importazione del pdb originale
        my $pdb = [ ];
        while (my $newline = shift @{$in_content}) {
            chomp $newline;
            if ($newline !~ /^ATOM/) {
                next;
            }
            
            # se le righe contengono le coordinate atomiche le parso...
            my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
            # Gli elementi del vettore @splitted da considerare sono:
            #   [1]   Atom serial number
            #   [3]   Atom name
            #   [4]   Alternate location indicator
            #   [5]   Residue name
            #   [7]   Chain identifier
            #   [8]   Residue sequence number
            #   [9]   Code for insertion of residues
            #   [11-13] XYZ coordinates
            #   [14]  Occupancy volume
            #   [15]  T-factor
            push(@{$pdb}, [ @splitted ]);
        }
        
        # pre-processamento del pdb
        my @Nterms; # res N-terminali
        my @Cterms; # res C-terminali
        for (my $i = 0; $i < scalar @{$pdb}; $i++) {
            if ($pdb->[$i][3] =~ /\sN\s{2}/) { # individui gli N-term
                if ($pdb->[$i+1][3] =~ /\sH1\s{1}/) {
                    push(@Nterms, $pdb->[$i][7].$pdb->[$i][8]); # mi appunto catena+resID 
                }
            } elsif ($pdb->[$i][3] =~ /\sC\s{2}/) { # individui i C-term
                if ($pdb->[$i+1][3] =~ /\sO1\s{1}/) {
                    push(@Cterms, $pdb->[$i][7].$pdb->[$i][8]);
                }
            }
        }
        
        # fix per le istidine
        my $fixc = 0E0; my $fixn = 0E0;
        for (my $i = 0; $i < scalar @{$pdb}; $i++) {
            if ($pdb->[$i][5] =~ /^HIS$/) {
                my $pattern = $pdb->[$i][7].$pdb->[$i][8];
                
                foreach my $ref (@Cterms) { # correzione per residui C-terminali
                    if ( $pattern =~ /$ref/) {
                        $fixc = 1;
                    }
                }
                foreach my $ref (@Nterms) { # correzione per residui N-terminali
                    if ( $pattern =~ /$ref/) {
                        $fixn = 2;
                    }
                }
                
                if ($pdb->[$i + 6 + $fixn][3] !~ /HD1/ && $pdb->[$i + 9 + $fixn][3] =~ /HE2/) {
                    for (my $a = $i; $a <= $i + 11 + $fixc + $fixn; $a++) {
                        $pdb->[$a][5] = 'HIE';
                    }
                } elsif ($pdb->[$i + 6 + $fixn][3] =~ /HD1/ && $pdb->[$i + 10 + $fixn][3] =~ /C/) {
                    for (my $a = $i; $a <= $i + 11 + $fixc + $fixn; $a++) {
                        $pdb->[$a][5] = 'HID';
                    }
                } else {
                    for (my $a = $i; $a <= $i + 12 + $fixc + $fixn; $a++) {
                        $pdb->[$a][5] = 'HIP';
                    }
                }
                $fixc = 0E0;
                $fixn = 0E0;
            }
        }
        
        # fix per le isoleucine
        for (my $i = 0; $i < scalar @{$pdb}; $i++) {
            if ($pdb->[$i][5] =~ /^ILE$/ && $pdb->[$i][3] =~ /^ CD $/) {
                $pdb->[$i][3] = ' CD1';
            }
        }
        
        # fix per le cisteine
        # raccolgo le info sugli atomi di zolfo delle cisteine
        my $SG = [ ];
        for (my $i = 0; $i < scalar @{$pdb}; $i++) {
            if ($pdb->[$i][5] =~ /^CYS$/ && $pdb->[$i][3] =~ /^ SG $/) {
                push(@{$SG}, $pdb->[$i]);
            }
        }
        # verifico la presenza di ponti disolfuro
        my %bridge;
        for (my $i = 0; $i < scalar @{$SG}; $i++) {
            for (my $j = $i + 1; $j < scalar @{$SG}; $j++) {
                my $xa = $SG->[$i][11]; $xa =~ s/\s//g; my $xb = $SG->[$j][11]; $xb =~ s/\s//g;
                my $ya = $SG->[$i][12]; $ya =~ s/\s//g; my $yb = $SG->[$j][12]; $yb =~ s/\s//g;
                my $za = $SG->[$i][13]; $za =~ s/\s//g; my $zb = $SG->[$j][13]; $zb =~ s/\s//g;
                my $distance = ($xa - $xb)**2 + ($ya - $yb)**2 + ($za - $zb)**2;
                $distance = sqrt $distance;
                # print "\n Distanza di legame: [$distance]";
                if ($distance < 2.1) { # se c'è il disuolfuro metto le cisteine in lista
                    my $key1 = $SG->[$i][7].$SG->[$i][8];
                    my $key2 = $SG->[$i][7].$SG->[$i][8];
                    $bridge{$key1} = 1 unless (exists $bridge{$key1});
                    $bridge{$key2} = 1 unless (exists $bridge{$key2});
                }
            }
        }
        for (my $i = 0; $i < scalar @{$pdb}; $i++) { # il fix vero e proprio
            my $pattern = $pdb->[$i][7].$pdb->[$i]->[8];
            if (exists $bridge{$pattern}) {
                $pdb->[$i][5] = 'CYX';
            }
        }
        
        # fix per i carbossili C-term
        for (my $i = 0; $i < scalar @{$pdb}; $i++) {
            my $pattern = $pdb->[$i][7].$pdb->[$i]->[8];
            foreach my $ref (@Cterms) { # aggiungo un "TER" ad ogni fine catena
                if ($pattern =~ /$ref/ && $pdb->[$i][3] =~ /^ O1 $/) {
                    $pdb->[$i][3] = ' O  ';
                } elsif ($pattern =~ /$ref/ && $pdb->[$i][3] =~ /^ O2 $/) {
                    $pdb->[$i][3] = ' OXT';
                }
            }
        }
        
        # rimozione degli idrogeni
        my $pdb_noH = [ ];
        while (my $newline = shift @{$pdb}) {
            if ($newline->[3] =~ /^H/ ) {
                next;
            } elsif ($newline->[3] =~ /^.H/ ) {
                next;
            } else {
                push(@{$pdb_noH}, $newline);
            }
        }
        
        # rinumero gli atomi
        my $i = 1;
        foreach my $newline (@{$pdb_noH}) {
            $newline->[1] = sprintf("% 5d",$i); # riempio a sinistra con degli spazi
            $i++;
        }
        
        # rinomino le catene
        my @letters = ('A'..'Z');
        my @newNterms;
        my $next_change = shift @Nterms;
        my $actual_chain;
        foreach my $newline (@{$pdb_noH}) {
            if ($newline->[7].$newline->[8] eq $next_change) {
                $actual_chain = shift @letters;
                push(@newNterms, $actual_chain.$newline->[8]);
                if (@Nterms) {
                    $next_change = shift @Nterms;
                } else {
                    $next_change = "goto_EOF"; # non ci sono altre catene rimanenti
                }
            }
            $newline->[7] = $actual_chain;
        }
        
        # scrittura del pdb processato
        $self->set_filename($self->get_workdir . '/snapshot.AMBER.pdb');
        my $path = $self->get_workdir();
        my $frame = $opt->{'frame'};
        my ($id) = $path =~ /\/([\w\.\s\-_]+)\/BRENDA\/$frame$/;
        my $out_content = [ "TITLE     $id t= $frame\n", "REMARK    generated by RAMBO - Routines AMBer Oriented\n", "MODEL        0\n" ];
        shift @newNterms;
        while (my $newline = shift @{$pdb_noH}) {
            my $pattern = $newline->[7].$newline->[8];
            foreach my $ref (@newNterms) { # aggiungo un "TER" ad ogni fine catena
                if ( $pattern =~ /$ref/) {
                    push(@{$out_content}, "TER\n");
                    shift @newNterms;
                }
            }
            my $joined = pack('A6A5A1A4A1A3A1A1A4A1A3A8A8A8A6A6A4A2A2', @{$newline});
            push(@{$out_content}, $joined."\n");
        }
        push(@{$out_content}, "TER\n");
        push(@{$out_content}, "ENDMDL\n");
        $self->write('filedata' => $out_content);
    }
}

sub topology {
# preparo i file di topologia per AMBER
    my ($self) = @_;
    
    my $pdb = $self->get_workdir . '/snapshot.AMBER.pdb'; # struttura di riferimento
    unless (-e $pdb) {
        $self->_raise_warning("\nE- file [$pdb] not found\n\n");
        return 1;
    }
    
    # templato del file di configurazione
    my $leaprc_template = <<END
logFile leap.log

addAtomTypes {
    { "H"   "H" "sp3" }
    { "HO"  "H" "sp3" }
    { "HS"  "H" "sp3" }
    { "H1"  "H" "sp3" }
    { "H2"  "H" "sp3" }
    { "H3"  "H" "sp3" }
    { "H4"  "H" "sp3" }
    { "H5"  "H" "sp3" }
    { "HW"  "H" "sp3" }
    { "HC"  "H" "sp3" }
    { "HA"  "H" "sp3" }
    { "HP"  "H" "sp3" }
    { "OH"  "O" "sp3" }
    { "OS"  "O" "sp3" }
    { "O"   "O" "sp2" }
    { "O2"  "O" "sp2" }
    { "OW"  "O" "sp3" }
    { "CT"  "C" "sp3" }
    { "CH"  "C" "sp3" }
    { "C2"  "C" "sp3" }
    { "C3"  "C" "sp3" }
    { "C"   "C" "sp2" }
    { "C*"  "C" "sp2" }
    { "CA"  "C" "sp2" }
    { "CB"  "C" "sp2" }
    { "CC"  "C" "sp2" }
    { "CN"  "C" "sp2" }
    { "CM"  "C" "sp2" }
    { "CK"  "C" "sp2" }
    { "CQ"  "C" "sp2" }
    { "CD"  "C" "sp2" }
    { "CE"  "C" "sp2" }
    { "CF"  "C" "sp2" }
    { "CP"  "C" "sp2" }
    { "CI"  "C" "sp2" }
    { "CJ"  "C" "sp2" }
    { "CW"  "C" "sp2" }
    { "CV"  "C" "sp2" }
    { "CR"  "C" "sp2" }
    { "CA"  "C" "sp2" }
    { "CY"  "C" "sp2" }
    { "C0"  "C" "sp2" }
    { "MG"  "Mg" "sp3" }
    { "N"   "N" "sp2" }
    { "NA"  "N" "sp2" }
    { "N2"  "N" "sp2" }
    { "N*"  "N" "sp2" }
    { "NP"  "N" "sp2" }
    { "NQ"  "N" "sp2" }
    { "NB"  "N" "sp2" }
    { "NC"  "N" "sp2" }
    { "NT"  "N" "sp3" }
    { "N3"  "N" "sp3" }
    { "S"   "S" "sp3" }
    { "SH"  "S" "sp3" }
    { "P"   "P" "sp3" }
    { "LP"  ""  "sp3" }
    { "F"   "F" "sp3" }
    { "CL"  "Cl" "sp3" }
    { "BR"  "Br" "sp3" }
    { "I"   "I"  "sp3" }
    { "FE"  "Fe" "sp3" }
        { "IM"  "Cl" "sp3" }
        { "IP"  "Na" "sp3" }
        { "Li"  "Li"  "sp3" }
        { "K"  "K"  "sp3" }
        { "Rb"  "Rb"  "sp3" }
        { "Cs"  "Cs"  "sp3" }
        { "Zn"  "Zn"  "sp3" }
        { "IB"  "Na"  "sp3" }
    { "H0"  "H" "sp3" }

}

parm99 = loadamberparams parm99.dat
frcmod03 = loadamberparams frcmod.ff03

loadOff ions94.lib
loadOff solvents.lib
HOH = TP3
WAT = TP3

loadOff all_aminoct03.lib
loadOff all_aminont03.lib
loadOff all_amino03.lib

addPdbResMap {
  { 0 "ALA" "NALA" } { 1 "ALA" "CALA" }
  { 0 "ARG" "NARG" } { 1 "ARG" "CARG" }
  { 0 "ASN" "NASN" } { 1 "ASN" "CASN" }
  { 0 "ASP" "NASP" } { 1 "ASP" "CASP" }
  { 0 "CYS" "NCYS" } { 1 "CYS" "CCYS" }
  { 0 "CYX" "NCYX" } { 1 "CYX" "CCYX" }
  { 0 "GLN" "NGLN" } { 1 "GLN" "CGLN" }
  { 0 "GLU" "NGLU" } { 1 "GLU" "CGLU" }
  { 0 "GLY" "NGLY" } { 1 "GLY" "CGLY" }
  { 0 "HID" "NHID" } { 1 "HID" "CHID" }
  { 0 "HIE" "NHIE" } { 1 "HIE" "CHIE" }
  { 0 "HIP" "NHIP" } { 1 "HIP" "CHIP" }
  { 0 "ILE" "NILE" } { 1 "ILE" "CILE" }
  { 0 "LEU" "NLEU" } { 1 "LEU" "CLEU" }
  { 0 "LYS" "NLYS" } { 1 "LYS" "CLYS" }
  { 0 "MET" "NMET" } { 1 "MET" "CMET" }
  { 0 "PHE" "NPHE" } { 1 "PHE" "CPHE" }
  { 0 "PRO" "NPRO" } { 1 "PRO" "CPRO" }
  { 0 "SER" "NSER" } { 1 "SER" "CSER" }
  { 0 "THR" "NTHR" } { 1 "THR" "CTHR" }
  { 0 "TRP" "NTRP" } { 1 "TRP" "CTRP" }
  { 0 "TYR" "NTYR" } { 1 "TYR" "CTYR" }
  { 0 "VAL" "NVAL" } { 1 "VAL" "CVAL" }
  { 0 "HIS" "NHIS" } { 1 "HIS" "CHIS" }
  { 0 "GUA" "DG5"  } { 1 "GUA" "DG3"  } { "GUA" "DG" }
  { 0 "ADE" "DA5"  } { 1 "ADE" "DA3"  } { "ADE" "DA" }
  { 0 "CYT" "DC5"  } { 1 "CYT" "DC3"  } { "CYT" "DC" }
  { 0 "THY" "DT5"  } { 1 "THY" "DT3"  } { "THY" "DT" }
  { 0 "G" "RG5"  } { 1 "G" "RG3"  } { "G" "RG" } { "GN" "RGN" }
  { 0 "A" "RA5"  } { 1 "A" "RA3"  } { "A" "RA" } { "AN" "RAN" }
  { 0 "C" "RC5"  } { 1 "C" "RC3"  } { "C" "RC" } { "CN" "RCN" }
  { 0 "U" "RU5"  } { 1 "U" "RU3"  } { "U" "RU" } { "UN" "RUN" }
  { 0 "DG" "DG5"  } { 1 "DG" "DG3"  }
  { 0 "DA" "DA5"  } { 1 "DA" "DA3"  }
  { 0 "DC" "DC5"  } { 1 "DC" "DC3"  }
  { 0 "DT" "DT5"  } { 1 "DT" "DT3"  }

}

addPdbAtomMap {
  { "O5*" "O5'" }
  { "C5*" "C5'" }
  { "C4*" "C4'" }
  { "O4*" "O4'" }
  { "C3*" "C3'" }
  { "O3*" "O3'" }
  { "C2*" "C2'" }
  { "O2*" "O2'" }
  { "C1*" "C1'" }
  { "C5M" "C7"  }
  { "H1*" "H1'" }
  { "H2*1" "H2'1" }
  { "H2*2" "H2'2" }
  { "H2'"  "H2'1" }
  { "H2''" "H2'2" }
  { "H3*" "H3'" }
  { "H4*" "H4'" }
  { "H5*1" "H5'1" }
  { "H5*2" "H5'2" }
  { "H5'"  "H5'1" }
  { "H5''" "H5'2" }
  { "HO2'" "HO'2" }
  { "HO5'" "H5T" }
  { "HO3'" "H3T" }
  { "O1'" "O4'" }
  { "OA"  "O1P" }
  { "OB"  "O2P" }
  { "OP1" "O1P" }
  { "OP2" "O2P" }
}

NHIS = NHIE
HIS = HIE
CHIS = CHIE
protein = loadpdb $pdb
saveamberparm  protein prot.prmtop prot.inpcrd
quit
END
    ;
    
    $self->set_filename($self->get_workdir() . '/leaprc.ff03');
    $self->write('filedata' => [ $leaprc_template ]);
    
    # lancio tleap
    my $dest_path = $self->get_workdir();
    my $tleap = $self->get_tleap();
    my $amberlog = qx/cd $dest_path; $tleap -s -f leaprc.ff03 2>&1/;
    $self->set_filename($dest_path . $self->get_logfile());
    $self->write( 'mode' => '>>', 'filedata' => [ "\n\n*** TLEAP ***\n", $amberlog ] );
}

1;