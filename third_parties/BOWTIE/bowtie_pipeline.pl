#!/usr/bin/perl
# -d

use strict;
use warnings;
use Carp;

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

##################################################################
use Cwd;
use threads;

#######################
## VARIABILI GLOBALI ##
our $index_basename = { # lista degli index_basename
                        all_genome          => '/analysis/db/blast/Bowtie/hg19/hg19',
                        all_mRNA            => '/analysis/db/blast/Hs_UCSC_mRNA/mrna.fa',
                        CCDS                => '/analysis/db/blast/Hs_CCDS/CCDS_nucleotide',
                        coding_RefSeq       => '/analysis/db/blast/Hs_Refseq/hg19/hg19_codingRefseq',
                        noncoding_RefSeq    => '/analysis/db/blast/Hs_Refseq/hg19/hg19_noncodingRefseq',
                        EST                 => '/analysis/db/blast/Hs_EST/Hs.est.fa',
                        tRNA                => '/analysis/db/blast/Hs_ncRNA/tRNA.hs',
                        rRNA                => '/analysis/db/blast/Hs_ncRNA/rRNA',
                        snoRNA              => '/analysis/db/blast/Hs_ncRNA/snoRNA.hs',
                        miRNA               => '/analysis/db/blast/Mirbase/rel_16/hairpin.hsa',
};


our $base_dir = getcwd; # working path
our $job_dir = { # path dove vengono memorizzati gli output dei vari job
                 all_genome          => $base_dir . '/STEP_1_Dataset',
                 all_mRNA            => $base_dir . '/STEP_2_mrna.fa',
                 CCDS                => $base_dir . '/STEP_3a_CCDS_nucleotide',
                 miRNA               => $base_dir . '/STEP_3b_all.mirna.hs.nr',
                 rRNA                => $base_dir . '/STEP_3c_rRNA',
                 tRNA                => $base_dir . '/STEP_3d_tRNA.hs',
                 snoRNA              => $base_dir . '/STEP_3e_snoRNA.hs',
                 EST                 => $base_dir . '/STEP_3f_Hs.est.fa',
                 coding_RefSeq       => $base_dir . '/STEP_4a_hg19_codingRefseq',
                 noncoding_RefSeq    => $base_dir . '/STEP_4b_hg19_noncodingRefseq',
};
our $paired_switch; # swtich per usare la pipeline con le paired reads
our $base_reads = [ ]; # nome dei file delle reads
our $paired_reads = { readsA => [ ], readsB => [ ]}; # raggruppo i file delle paired reads
our $bowtie_opt = ' -t -n2 -q -p4 --best -B1 '; # opzioni usate di default (job single read) nella riga di comando per bowtie
our $bowtie_bin = ''; # path del file binario bowtie (se vuoto prova viene inizializzato con il comando "which bowtie")
our @thr; # elenco dei threads attivi (x gli step di parallelizzazione);
# TOPHAT GLOBALS (solo x la modalità paired mode al momento)
our $tophat_bin = ''; # path del file binario tophat (se vuoto prova viene inizializzato con il comando "which tophat")
our $tophat_outputs = $job_dir->{all_genome} . '/tophat_out'; # directory dei file di output
our $tophat_gap; # distanza media (in bp) tra le coppie di reads; v. USAGE
our $tophat_stdev = 20; # deviazione standard della distribuzione della lunghezza dei frammenti; v. USAGE
our $tophat_xp; # se definito, implementa il butterfly-search algorithm; v. USAGE
#######################

USAGE: {
    use Getopt::Long;no warnings;
    my $options= { };
    GetOptions($options, 'help|h', 'paired|p', 'gap|g=i', 'stdev|s=i', 'butterfly|b');#, 'threads|n=i', 'workdir|d=s');
    my $usage = <<END

SYNOPSYS

  $0 [options] <reads_pattern>

OPTIONS

  -p|paired         specifica se avviare la pipeline usando come input files 
                    contenenti paired reads
  
  -g|gap <int>      [TopHat] (OBBLIGATORIO, v. la sezione "NOTES") distanza 
                    media (in bp) tra le coppie di reads, viene calcolata come 
                            [lunghezza_frammento]-2*[lunghezza_read] 
                    consultare la documentazione allegata ai file delle paired 
                    reads x impostare questo parametro.
  
  -s|stdev <int>    [TopHat] (default 20bp) deviazione standard della 
                    distribuzione della lunghezza dei frammenti; consultare la 
                    documentazione allegata ai file delle paired reads x 
                    impostare questo parametro.
  
  -b|butterfly      [TopHat] algoritmo aggiuntivo più lento ma maggiormente 
                    sensibile; da usare se ci si aspetta che l'esperimento 
                    abbia prodotto molti pre-mRNA (annotazioni nella 
                    documentazione allegata ai file delle paired reads del 
                    tipo "polyA+..." non consente stabilire se il RNA sia già 
                    processato)

NOTES:
  
  Attualmente TopHat viene implementato solo quando la pipeline viene lanciata 
  in paired read mode.
END
    ;
    $paired_switch = 1 if (exists $options->{paired});
    if ((exists $options->{help})||!$ARGV[0]) {
        print $usage; exit;
    }
    if ($paired_switch) {
        unless (exists $options->{gap}) {
            print $usage; exit;
        }
        $tophat_gap = $options->{gap};
        $tophat_stdev = $options->{stdev} if (exists $options->{stdev});
        $tophat_xp = 1 if (exists $options->{butterfly});
    }
}

FILE_CHEK: {
    
    BOWTIE_BIN: { # controllo che il path di bowtie sia corretto...
        chomp($bowtie_bin = qx/which bowtie/) unless ($bowtie_bin);
        croak ("\nE- ERROR bowtie binary file <$bowtie_bin> non trovato\n") unless (-e $bowtie_bin);
    }
    
    TOPHAT_BIN: { # controllo che il path di tophat sia corretto...
        chomp($tophat_bin = qx/which tophat/) unless ($tophat_bin);
        if ($paired_switch) {
            croak ("\nE- ERROR tophat binary file <$tophat_bin> non trovato\n") unless (-e $tophat_bin);
        } else {
            carp ("\nW- WARNING tophat binary file <$tophat_bin> non trovato\n") unless (-e $tophat_bin);
        }
    }
    
    INDEX_FILES: { # verifico che siano presenti tutti gli index_basename
        my $not_found = 0;
        #~ print Dumper $index_basename; 
        foreach my $dataset (keys (%$index_basename)) {
            unless (-e ($index_basename->{$dataset}.'.rev.2.ebwt')) {
                print "\n-- ERROR index basename <$index_basename->{$dataset}> non trovato";
                $not_found ++;
            }
        }
        croak '\n-- ERROR pipeline abortita' if ($not_found > 0);
    }
    
    READS_FILES: { # cerco i file delle reads
        my ($path, $dh); 
        if ($ARGV[0] =~ /\//) {
            ($path) = $ARGV[0] =~ /(.*)\/.*$/g;
            croak ("\n-- ERROR path <$path> non trovato\n") unless (chdir $path);
        };
        $path = getcwd;
        opendir ($dh, $path);
        my @file_list = readdir($dh);
        closedir $dh;
        my ($pattern) = $ARGV[0] =~ /([^\/]*)$/g;
        @file_list = grep /$pattern/, @file_list or croak "\n-- ERROR pattern dei file delle reads <$ARGV[0]> non trovato\n";
        @$base_reads = map { $path.'/'.$_} @file_list;
        #~ print Dumper $base_reads;
    }
    
    PAIRED_FILES: { # raggruppo i file delle paired reads
        if ($paired_switch) {
            @{$paired_reads->{readsA}} = grep /_1.fastq$/, @$base_reads 
                or croak "\nE- ERROR impossibile distinguere i file delle paired_reads\n";
            @{$paired_reads->{readsB}} = grep /_2.fastq$/, @$base_reads 
                or croak "\nE- ERROR impossibile distinguere i file delle paired_reads\n";
        }
    }
}

############################
# RIGHE DI TESTING
# goto STEP_200;
# STEP_200: { print "\n_________________\nFINE PROGRAMMA\n"; }
############################


############################
####  INIZIO PIPELINE   ####
############################
print "\n-- INIZIO PIPELINE...";

PAIRED_INIT: { # setup della pipeline x gestire le paired reads
    if ($paired_switch) {
        print "\nW- paired read mode";
#         opzioni per il paired read job
#             in questa modalità bowtie NON accetta l'opzione "--best"
#             "-k<int>"  riporto <int> allineamenti per coppia di reads
#             "-m<int>"  non vengono presi in considerazione le coppie di reads che presentano più di <int> allineamenti (lo imposto a 40, valore di default in TopHat, programma in cui è incapsulato Bowtie)
        $bowtie_opt = ' -t -n2 -q -p4 -k1 -m40 -B1 ';
        
#         ordino le liste delle reads
        @{$paired_reads->{readsA}} = sort {$a cmp $b} @{$paired_reads->{readsA}};
        @{$paired_reads->{readsB}} = sort {$a cmp $b} @{$paired_reads->{readsB}};
        
#         mi accerto che non ci siano file di reads spaiati        
        use bowtie_scripts::Parse_Array; # ATTENZIONE: ricordarsi di aggiornare la variabile d'ambiente $PERL5LIB nel file .bashrc
        my $couple = bowtie_scripts::Parse_Array->new();
        my @arrayA = @{$paired_reads->{readsA}};
        my @arrayB = @{$paired_reads->{readsB}};
        map { my $elem = $_; $elem =~ s/_1.fastq$/_n.fastq/; $_ = $elem } @arrayA;
        map { my $elem = $_; $elem =~ s/_2.fastq$/_n.fastq/; $_ = $elem } @arrayB;
        $couple->set_array_A(\@arrayA);
        $couple->set_array_B(\@arrayB);
        my %differences = %{$couple->compare()};
        my @unpaired = (@{$differences{'only_A'}}, @{$differences{'only_B'}});
        if ((scalar(@unpaired)) >= 1) {
            print "\n\nE- ERROR coppie di files paired reads incomplete:";
            foreach (@unpaired) { print "\n\t$_"; }
            croak "\n";
        }

    } else {
        print "\nW- single read mode";
    }
}

STEP_1: { # mappatura delle reads iniziali vs. tutto il genoma
    print "\n-- STEP_1 avviato...\n";
    mkdir $job_dir->{all_genome};
    my ($cmd_bowtie, $cmd_tophat);
    if ($paired_switch) {
        my ($mateA, $mateB) = (join(',', @{$paired_reads->{readsA}}), join(',', @{$paired_reads->{readsB}}));
        $cmd_bowtie = bowtie_string( path    => $job_dir->{all_genome},
                                     index   => $index_basename->{all_genome},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => $bowtie_opt );
        $cmd_tophat = tophat_string( index   => $index_basename->{all_genome},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => '' );
        push @thr, threads->new(\&run_cmd, $cmd_bowtie);
        push @thr, threads->new(\&run_cmd, $cmd_tophat);
    } else {
        my $reads = join(',', @{$base_reads});
        $cmd_bowtie = bowtie_string( path    => $job_dir->{all_genome},
                                     index   => $index_basename->{all_genome},
                                     reads   => $reads,
                                     options => $bowtie_opt );
        run_cmd($cmd_bowtie);
    }
}

if ($paired_switch) {
    for (@thr) { $_->join() }; # attendo che i threads lanciati siano terminati
    @thr = ( ); # svuoto la lista dei threads x riciclarla in futuro
}
print "\n-- STEP_1 concluso\n";

STEP_2: { # mappatura di Hg_mappable vs. tutti gli mrna
    print "\n-- STEP_2 avviato...\n";
    mkdir $job_dir->{all_mRNA};
    my $cmd_string;
    if ($paired_switch) {
        my $mateA = $job_dir->{all_genome} . '/aligned_1.fastq';
        my $mateB = $job_dir->{all_genome} . '/aligned_2.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{all_mRNA},
                                     index   => $index_basename->{all_mRNA},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => $bowtie_opt );
    } else {
        my $reads = $job_dir->{all_genome} . '/aligned.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{all_mRNA},
                                     index   => $index_basename->{all_mRNA},
                                     reads   => $reads,
                                     options => $bowtie_opt );
    }
    run_cmd($cmd_string);
    print "\n-- STEP_2 concluso\n";
}

STEP_3a: { # mappatura di All mRNA match vs. CCDS
    print "\n-- STEP_3a avviato...\n";
    mkdir $job_dir->{CCDS};
    my $cmd_string;
    if ($paired_switch) {
        my $mateA = $job_dir->{all_mRNA} . '/aligned_1.fastq';
        my $mateB = $job_dir->{all_mRNA} . '/aligned_2.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{CCDS},
                                     index   => $index_basename->{CCDS},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => $bowtie_opt );
    } else {
        my $reads = $job_dir->{all_mRNA} . '/aligned.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{CCDS},
                                     index   => $index_basename->{CCDS},
                                     reads   => $reads,
                                     options => $bowtie_opt );
    }
    push @thr, threads->new(\&run_cmd, $cmd_string);
}

STEP_3b: { # mappatura di All mRNA unmatch vs. miRNA
    print "\n-- STEP_3b avviato...\n";
    mkdir $job_dir->{miRNA};
    my $cmd_string;
    if ($paired_switch) {
        my $mateA = $job_dir->{all_mRNA} . '/unaligned_1.fastq';
        my $mateB = $job_dir->{all_mRNA} . '/unaligned_2.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{miRNA},
                                     index   => $index_basename->{miRNA},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => $bowtie_opt );
    } else {
        my $reads = $job_dir->{all_mRNA} . '/unaligned.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{miRNA},
                                     index   => $index_basename->{miRNA},
                                     reads   => $reads,
                                     options => $bowtie_opt );
    }
    push @thr, threads->new(\&run_cmd, $cmd_string);
}

STEP_3c: { # mappatura di All mRNA unmatch vs. rRNA
    print "\n-- STEP_3c avviato...\n";
    mkdir $job_dir->{rRNA};
    my $cmd_string;
    if ($paired_switch) {
        my $mateA = $job_dir->{all_mRNA} . '/unaligned_1.fastq';
        my $mateB = $job_dir->{all_mRNA} . '/unaligned_2.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{rRNA},
                                     index   => $index_basename->{rRNA},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => $bowtie_opt );
    } else {
        my $reads = $job_dir->{all_mRNA} . '/unaligned.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{rRNA},
                                     index   => $index_basename->{rRNA},
                                     reads   => $reads,
                                     options => $bowtie_opt );
    }
    push @thr, threads->new(\&run_cmd, $cmd_string);
}

STEP_3d: { # mappatura di All mRNA unmatch vs. tRNA
    print "\n-- STEP_3d avviato...\n";
    mkdir $job_dir->{tRNA};
    my $cmd_string;
    if ($paired_switch) {
        my $mateA = $job_dir->{all_mRNA} . '/unaligned_1.fastq';
        my $mateB = $job_dir->{all_mRNA} . '/unaligned_2.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{tRNA},
                                     index   => $index_basename->{tRNA},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => $bowtie_opt );
    } else {
        my $reads = $job_dir->{all_mRNA} . '/unaligned.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{tRNA},
                                     index   => $index_basename->{tRNA},
                                     reads   => $reads,
                                     options => $bowtie_opt );
    }
    push @thr, threads->new(\&run_cmd, $cmd_string);
}

STEP_3e: { # mappatura di All mRNA unmatch vs. snoRNA
    print "\n-- STEP_3e avviato...\n";
    mkdir $job_dir->{snoRNA};
    my $cmd_string;
    if ($paired_switch) {
        my $mateA = $job_dir->{all_mRNA} . '/unaligned_1.fastq';
        my $mateB = $job_dir->{all_mRNA} . '/unaligned_2.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{snoRNA},
                                     index   => $index_basename->{snoRNA},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => $bowtie_opt );
    } else {
        my $reads = $job_dir->{all_mRNA} . '/unaligned.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{snoRNA},
                                     index   => $index_basename->{snoRNA},
                                     reads   => $reads,
                                     options => $bowtie_opt );
    }
    push @thr, threads->new(\&run_cmd, $cmd_string);
}

STEP_3f: { # mappatura di All mRNA unmatch vs. EST
    print "\n-- STEP_3f avviato...\n";
    mkdir $job_dir->{EST};
    my $cmd_string;
    if ($paired_switch) {
        my $mateA = $job_dir->{all_mRNA} . '/unaligned_1.fastq';
        my $mateB = $job_dir->{all_mRNA} . '/unaligned_2.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{EST},
                                     index   => $index_basename->{EST},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => $bowtie_opt );
    } else {
        my $reads = $job_dir->{all_mRNA} . '/unaligned.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{EST},
                                     index   => $index_basename->{EST},
                                     reads   => $reads,
                                     options => $bowtie_opt );
    }
    push @thr, threads->new(\&run_cmd, $cmd_string);
}

for (@thr) { $_->join() }; # attendo che i threads lanciati siano terminati
@thr = ( ); # svuoto la lista dei threads x riciclarla in futuro
print "\n-- STEP_3 concluso\n";

STEP_4a: { # mappatura di CCDS unmatch vs. coding Refseq
    print "\n-- STEP_4a avviato...\n";
    mkdir $job_dir->{coding_RefSeq};
    my $cmd_string;
    if ($paired_switch) {
        my $mateA = $job_dir->{CCDS} . '/unaligned_1.fastq';
        my $mateB = $job_dir->{CCDS} . '/unaligned_2.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{coding_RefSeq},
                                     index   => $index_basename->{coding_RefSeq},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => $bowtie_opt );
    } else {
        my $reads = $job_dir->{CCDS} . '/unaligned.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{coding_RefSeq},
                                     index   => $index_basename->{coding_RefSeq},
                                     reads   => $reads,
                                     options => $bowtie_opt );
    }
    push @thr, threads->new(\&run_cmd, $cmd_string);
}

STEP_4b: { # mappatura di CCDS unmatch vs. noncoding Refseq
    print "\n-- STEP_4b avviato...\n";
    mkdir $job_dir->{noncoding_RefSeq};
    my $cmd_string;
    if ($paired_switch) {
        my $mateA = $job_dir->{CCDS} . '/unaligned_1.fastq';
        my $mateB = $job_dir->{CCDS} . '/unaligned_2.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{noncoding_RefSeq},
                                     index   => $index_basename->{noncoding_RefSeq},
                                     mateA   => $mateA,
                                     mateB   => $mateB,
                                     options => $bowtie_opt );
    } else {
        my $reads = $job_dir->{CCDS} . '/unaligned.fastq';
        $cmd_string = bowtie_string( path    => $job_dir->{noncoding_RefSeq},
                                     index   => $index_basename->{noncoding_RefSeq},
                                     reads   => $reads,
                                     options => $bowtie_opt );
    }
    push @thr, threads->new(\&run_cmd, $cmd_string);
}

for (@thr) { $_->join() }; # attendo che i threads lanciati siano terminati
@thr = ( ); # svuoto la lista dei threads x riciclarla in futuro
print "\n-- STEP_4 concluso\n";

print "\n-- FINE PIPELINE";
############################
####  FINE PIPELINE     ####
############################


STEP_200: { print "\n_________________\nFINE PROGRAMMA\n"; }
exit;


#  SUBROUTINES
############################

# routine che lancia comandi da shell
sub run_cmd {
    my ($cmd) = @_;
    warn("\n-- CMD $cmd\n");
    system("$cmd") && croak ("\n-- ERROR fail to run command <$cmd>");
}

############################
# SYNOPSYS di una riga di comando di bowtie:
# 
#     bowtie [options] <ebwt> {-1 <m1> -2 <m2> | --12 <r> | <s>} [<hit>]
#     
# [options]
#     è la lista di opzioni con cui viene lanciato bowtie. Alcune opzioni sono definite dalla variabile globale <$bowtie_opt>; le opzioni di output "--al" e "--un" sono definite nella subroutine <bowtie_string>.
# <ebwt>
#     OBBLIGATORIO: basename dell'index di riferimento su cui verranno allineate le reads; viene definito nella subroutine <bowtie_string>.
# {-1 <m1> -2 <m2> | --12 <r> | <s>}
#     OBBLIGATORIO: lista di 1 o + files contenenti le reads (elenco separato da virgole). Esistono tre modalità di input:
#         "<s>" per i jobs single reads;
#         "-1 <m1> -2 <m2>" per i jobs su paired reads; le liste di file <m1> e <m2> DEVONO essere elencate nello stesso ordine alfabetico (es.: <m1> = "C3_1.fastq,C4_1.fastq,C5_1.fastq" <m2> = "C3_2.fastq,C4_2.fastq,C5_2.fastq");
#         "--12 <r>" per i jobs su paired reads; le coppie di reads sono dentro un file tab separated.
#     Le liste di file vengono definite nella subroutine <bowtie_string>.
# [<hit>]
#     nome del file di output degli allineamenti; viene definito nella subroutine <bowtie_string>.
############################

# produce una stringa contenente il comando esteso per lanciare bowtie
sub bowtie_string {
# %arg = ( path    => $arg1, path dove verra' salvato l'output
#          index   => $arg2, index_basename
#          reads   => $arg3, lista di reads files (separati da virgola)
#          mateA   => $arg4, paired read mode: lista A di reads files (separati da virgola)
#          mateB   => $arg5, paired read mode: lista B di reads files (separati da virgola)
#          opt     => $arg6, opzioni aggiuntive (sono GIA' DEFINITE le seguenti opzioni: '--al' e '--un')
    my (%arg) = @_;
    
    # verifico che siano immessi i valori minimi per la subroutine
    foreach my $opt ('path', 'index') {
        unless (exists $arg{$opt}) {
            unless ((exists $arg{reads})||((exists $arg{mateA})&&(exists $arg{mateB}))) {
                my $exception = <<END
-- ERROR
Parametri mancanti, sintassi minima:
bowtie_string(path => \$arg1, index => \$arg2, {reads => \@arg3 | [mateA => \@arg3a, mateB => \@arg3b]} )

END
                ;
                croak $exception;
            }
        }
    }
    
    my $command_line = "$bowtie_bin $arg{options} ";
    $command_line .= "--al '$arg{path}/aligned.fastq' --un '$arg{path}/unaligned.fastq' ";
    $command_line .= "'$arg{index}' ";
    if ($paired_switch) {
        $command_line .= "-1 '$arg{mateA}' -2 '$arg{mateB}' ";
    } else {
        $command_line .= "'$arg{reads}' ";
    }
    $command_line .= "'$arg{path}/output.map' >> $arg{path}/run.log 2>&1";
    
    return $command_line;
}


############################
# SYNOPSYS di una riga di comando di tophat:
# 
#     tophat [options] <index_base> <reads1_1[,...,readsN_1]> [reads1_2,...readsN_2] 
#     
# [options]
#     è la lista di opzioni con cui viene lanciato tophat. Alcune opzioni sono definite da variabili globali <$tophat_...>;
# <index_base>
#     OBBLIGATORIO: basename dell'index di riferimento su cui verranno allineate le reads; viene definito nella subroutine <bowtie_string>.
# <reads1_1[,...,readsN_1]>
#     OBBLIGATORIO: lista di 1 o + files contenenti le reads (elenco separato da virgole).
# [reads1_2,...readsN_2]
#     OPZIONALE: lista di 1 o + files contenenti le reads (elenco separato da virgole) nel caso di paired reads. In questo caso le liste <reads1_1[,...,readsN_1]> e [reads1_2,...readsN_2] siano com DEVONO essere elencate nello stesso ordine alfabetico.
############################

# produce una stringa contenente il comando esteso per lanciare tophat
sub tophat_string {
# %arg = ( index   => $arg1, index_basename
#          mateA   => $arg2, paired read mode: lista A di reads files (separati da virgola)
#          mateB   => $arg3, paired read mode: lista B di reads files (separati da virgola)
#          opt     => $arg4, opzioni aggiuntive
    my (%arg) = @_;
    
    # verifico che siano immessi i valori minimi per la subroutine
    foreach my $opt ('mateA', 'mateB', 'index') {
        unless (exists $arg{$opt}) {
            my $exception = <<END
-- ERROR
Parametri mancanti, sintassi minima:
tophat_string(index => \$arg1, mateA => \@arg2, mateB => \@arg3)

END
            ;
            croak $exception;
            
        }
    }
    
    my $command_line = "$tophat_bin -p 4 -o $tophat_outputs -r $tophat_gap --mate-std-dev $tophat_stdev ";
    $command_line .= "--butterfly-search " if ($tophat_xp);
    $command_line .= "'$arg{index}' ";
    $command_line .= "'$arg{mateA}' '$arg{mateB}' ";
    $command_line .= " >> $job_dir->{all_genome}/tophat_run.log 2>&1";
    
    return $command_line;
}