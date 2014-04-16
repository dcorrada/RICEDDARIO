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

###################################################################
use Cwd;
use Carp;
use RICEDDARIO::lib::FileIO;

#######################
## VARIABILI GLOBALI ##
our $working_dir = getcwd();
our $filename = { 'xpm' => 'ss.xpm', 'dat' => 'ssdump.dat', 'csv' => 'sstruct.csv' };
our $chains = [ '1' ]; # lista delle posizioni di inizio delle catene del polipeptide
our $structs = { }; # hash contenente le info da scrivere in output
our $file_obj = RICEDDARIO::lib::FileIO->new();
our $alphabet = { # codici usati per generare la pixmap
    'E' => 'Strand',
    'B' => 'Strand',
    'S' => 'Loop',
    'T' => 'Loop',
    '~' => 'Loop',
    'H' => 'Helix',
    'I' => 'Helix',
    'G' => 'Helix'
};
our $res_number; # numero totale di residui
our $timing; # durata delle simulazione
#######################


USAGE: {
    my $options = { };
    use Getopt::Long;no warnings;
    GetOptions($options, 'help|h', 'input|i=s', 'dump|d=s', 'output|o=s','chain|c=i@');
    my $usage = <<END

SYNOPSYS

  $0 [-f string] [-d string] [-o string] [-c int]

Questo script si occupa di fare un parsing dei file di output dati dal comando
di GROMACS "do_dssp". Restituisce un file .csv con la lista dei residui, la
percentuale del tempo in cui si trovano in una struttura e, di conseguenza, in
quale struttura si trovano prevalentemente durante tutta la simulazione 

OPZIONI

  -i <string>       INPUT, XPixMap filename (def: 'ss.xpm')

  -d <string>       INPUT, .dat filename (def: 'ssdump.dat')

  -o <string>       OUTPUT, .csv filename (def: 'sstruct.csv')

  -c <int1> <int2>  lista delle posizioni dei residui iniziali di ogni catena
                    (nei casi in cui si ha ha che fare con un polipeptide)

ESEMPI:
   
   $0 -c 211 -c 346
   # il mio sistema e' costituito da 3 catene: la prima parte dal residuo '1',
   # la seconda dal residuo '211', la terza dal residuo '346'

END
    ;
    if (exists $options->{'help'}) { print $usage; exit; };

    $filename->{'xpm'} = $options->{'input'} if (exists $options->{'input'});
    $filename->{'dat'} = $options->{'dump'} if (exists $options->{'dump'});
    $filename->{'csv'} = $options->{'output'} if (exists $options->{'output'});
    
    push(@{$chains}, sort {$a <=> $b} @{$options->{'chain'}}) if (exists $options->{'chain'});
}

FILECHECK: {
    croak("\nE- file [$filename->{'xpm'}] not found\n\t") unless (-e $filename->{'xpm'});
    croak("\nE- file [$filename->{'dat'}] not found\n\t") unless (-e $filename->{'dat'});
}

PARSE_DAT: {
    printf("\nI- parsing <%s/%s>...", getcwd(), $filename->{'dat'});
    
    $file_obj->set_filename($filename->{'dat'});
    my $content = $file_obj->read();
    
    $res_number = $content->[0]; chomp $res_number;
    my $last_chain = $chains->[ scalar(@{$chains}) - 1 ];
    if ($last_chain > $res_number) { 
        carp("\nW- chain beginning [$last_chain] out of range\n\t");
        pop(@{$chains}); # ...quindi la elimino dalla list
    }
    
    my $seq = $content->[1]; chomp $seq;
    my @residues = split(//, $seq);
    
    # splitto la sequenza nelle rispettive catene
    my @start_list = @{$chains};
    while (my $start = shift @start_list) {
        my $end;
        if ($start_list[0]) {
            $end = $start_list[0] - 1;
        } else {
            $end = $res_number;
        }
        
        # inizializzo l'hash con identificatori di residuo e di catena
        my $chain_id = sprintf("CHAIN_%05d", $start);
        for(my $id = $start - 1; $id < $end; $id++) {
            my $res_id = sprintf("%05d", $id + 1);
            $structs->{$res_id} = {
                'CHAIN' => $chain_id,
                'MAJOR_CONF' => $alphabet->{$residues[$id]}, # annoto la conformazione predominante per lo speifico residuo
                'HELIX' => '',
                'STRAND'  => '',
                'LOOP' => ''
            };
        }
    }
    
    print "done\n";
}

PARSE_XPM: {
    printf("\nI- parsing <%s/%s>...", getcwd(), $filename->{'xpm'});
    
    $file_obj->set_filename($filename->{'xpm'});
    my $content = $file_obj->read();
    
    # mi prendo solo le righe che mi servino dal file .xpm
    my @info = @{$content};
    @info = splice(@info,scalar(@info)-($res_number));
    
    $timing = length($info[0]) - 4;
#     print "la simulazione dura ", $timing;
    
    # tiro via un elemento per volta a partire dall'ultimo (che in realtà è il primo residuo)
    my ($id, $res_id, $helix, $strand, $loop);
    while (my $string = pop(@info)) {
        chomp $string; $string =~ s/[\",]//g; # ripulisco la mia stringa
        
        $id++; $res_id = sprintf("%05d", $id);
#         print "\nadesso serviamo il residuo [$res_id]";
        
        # calcolo ora i valori percentuali di quanto tempo passa un residuo in che conformazione
        $helix = $string =~ tr/HIG/HIG/; $helix = $helix/$timing;
        $strand = $string =~ tr/EB/EB/; $strand = $strand/$timing;
        $loop = $string =~ tr/\~ST/\~ST/; $loop = $loop/$timing;
#         printf("\n[%s]\tH->%.2f\tS->%.2f\tL->%.2f", $res_id, $helix, $strand, $loop);
        
        $structs->{$res_id}->{'HELIX'} = sprintf("%.2f", $helix);
        $structs->{$res_id}->{'STRAND'} = sprintf("%.2f", $strand);
        $structs->{$res_id}->{'LOOP'} = sprintf("%.2f", $loop);
    }
    
    print "done\n";
}

RIEPILOGO: {
    print "\n/*";
    print "\nRESIDUES\t[$res_number]\nSAMPLES\t[$timing]";
    print "\nCHAINS\t";
    
    my @start_list = @{$chains};
    while (my $start = shift @start_list) {
        my $end;
        if ($start_list[0]) {
            $end = $start_list[0] - 1;
        } else {
            $end = $res_number;
        }
        printf("\t[%05d->%05d]", $start, $end);
    }
    print "\n*/\n";
}

WRITE_CSV: {
#     foreach my $key (sort keys %{$structs}) { print "\n[$key]\n", Dumper $structs->{$key}; }
    printf("\nI- writing output to <%s/%s>...", getcwd(), $filename->{'csv'});
    my $file_content = [ ];
    my @records = sort keys %{$structs};
    my $header = "RESIDUE;CHAIN;MAIN_CONF;HELIX;STRAND;LOOP\n";
    
    push(@{$file_content}, $header);
    while (my $row = shift @records) {
        my ($res_id) = $row =~ /^0+(\d+)$/;
        my $string = join(';', $res_id, $structs->{$row}->{'CHAIN'}, $structs->{$row}->{'MAJOR_CONF'}, $structs->{$row}->{'HELIX'}, $structs->{$row}->{'STRAND'}, $structs->{$row}->{'LOOP'}) . "\n";
        push(@{$file_content}, $string);
    }
    
    $file_obj->set_filename($filename->{'csv'});
    $file_obj->set_filedata($file_content);
    $file_obj->write();
    
    print "done\n";
}

FINE: {
    print "\n---\nFINE PROGRAMMA\n";
    exit;
}
