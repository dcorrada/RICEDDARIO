#!/usr/bin/perl

use strict;
use warnings;

################################################################################
# Questo script:
# 1 - legge i workflow progettati con FreeMind
# 2 - cerca i tag che identificano variabili e routine specifiche
# 3 - allestisce una serie di shell script basati sui tag
# 4 - lancia in parallelo script sh per ogni set di dati
# 
# Le regole e la nomeclatura dei tag (e di conseguenza la sintassi per disegnare 
# le mappe) possono diventare più o meno complesse a seconda dei task specifici.
# Considerate questo script alla stregua di un templato su cui sviluppare la 
# vostra interfaccia.

################################################################################
# Definisco i path degli script Perl di supporto al presente script
#
# "mm2xml.pl" mi serve per convertire un file .mm in un codice XML minimale
# contenente solo le info di interesse per far girare il flusso di lavoro
# progettato con FreeMind.
our $mm2xml = $ENV{'HOME'} . '/tmp/WORKFLOW/mm2xml.pl';
# "sh_scheduler.pl" mi servirà per lanciare in batch gli shell script contenenti
# i singoli job programmati per ogni set di dati.
our $sh_scheduler = $ENV{'HOME'} . '/tmp/WORKFLOW/sh_scheduler.pl';

################################################################################
# Importo il workflow progettato con FreeMind
our $mm2hash = { };
IMPORT_WOKFLOW: {
    # Leggo come primo argomento in input il nome del file mm
    $ARGV[0] or die "\nE- no FreeMind input file selected";
    my $mm_file = $ARGV[0];
    # Recupero il codice XML
    my $xml_code = qx/$mm2xml $mm_file/;
    # Converto l'XML in un hash
    use XML::Simple;
    $mm2hash = XMLin($xml_code);
    # Le seguenti righe di controllo mostrano come è strutturato l'hash importato
#     use Data::Dumper;
#     print Dumper $mm2hash;
#     exit;
}

################################################################################
# Individuo il tag del dataset e faccio un check sui subtag di ogni set di dati
our $DATASET = { };
CHECK_DATASET: {
    # Gestisco l'eccezione sollevata nel caso non esistesse nel file mm un tag 
    # chiamato "DATASET".
    # I subtag di "DATASET" definiscono il nome di ogni set di dati; a valle di
    # essi i tag figli descrivono il path e i nomi dei fili di input specifici.
    $DATASET = $mm2hash->{'WORKFLOW'}->{'DATASET'} or die "\nE- tag <DATASET> not found";
    foreach my $task (keys %{$DATASET}) {
        # La variabile $task contiene il tag che definisce il nome del set di dati
        # nel ciclo attuale
        $DATASET->{$task}->{'path'} or do {
            # Ogni set di dati deve contenere un tag che definisce il percorso di dove si 
            # dovrà leggere/scrivere i file di input/output (es.: "path=/my/dataset/path").
            # Se non trovo il tag non prendo in considerazione quel set di dati
            warn "\nW- <path> variable not defined, skipping task <$task>";
            delete $DATASET->{$task};
            next;
        };
        foreach my $vars (keys %{$DATASET->{$task}}) {
            next if ($vars eq 'path');
            my $filename = $DATASET->{$task}->{'path'} . '/' . $DATASET->{$task}->{$vars};
            -e $filename or do {
                # Ogni altro tag diverso da "path" descriverà il tipo e il nome dei file di input
                # presenti nella cartella associata al set di dati (es.: "xtc=nomefile.xtc").
                # Se il file non esiste non viene considerato, un'eccezione verrà sollevata
                # successivamente se tale file risulta necessario per lanciare un job.
                ################################################################################
                warn "\nW- file [$filename] not found, skipping";
                delete $DATASET->{$task}->{$vars};
                next;
            }
        }
    }
}

################################################################################
# Individuo il tag dei job e definisco le stringhe di comando per ognuno
our $JOBS_LIST = { };
CHECK_JOBS: {
    $mm2hash->{'WORKFLOW'}->{'JOBS'} or die "\nE- tag <JOBS> not found";
    foreach my $task (keys %{$DATASET}) {
        # Per ogni set di dati individuato da $DATASET->{$task} allestisco la lista dei
        # singoli job che verranno lanciati (ie i tag a valle di "JOBS").
        $JOBS_LIST->{$task} = [ ];
        foreach my $tag (keys %{$mm2hash->{'WORKFLOW'}->{'JOBS'}}) {
            # Ogni singolo job individuato da $tag identifica un comando/programma specifico
            # da lanciare.
            # In questo esempio prendo in considerazione solamente comandi di GROMACS
            my $job = $mm2hash->{'WORKFLOW'}->{'JOBS'}->{$tag};
            $_ = $tag;
            my $cmd_string;
            CASEOF: {
                /^g_rms$/ and do {
                    # Alcuni comandi di GROMACS sono interattivi e richiedono che vengano scelti
                    # in input gruppi definiti (richiamabili anche da un file ndx ad-hoc).
                    # Per aggirare l'approccio interattivo nel file mm dovrò aggiungere dei subtag
                    # del tipo "xxxgroup=n".
                    ($job->{'fit_group'} and $job->{'rmsd_group'}) or do {
                        warn "\nW- undef group for job <$tag> on <$task>, skipping";
                        undef $cmd_string;
                        last CASEOF;
                    };
                    # Le opzioni di GROMACS obbligatorie (-f;-s;etc) non prevedono l'inserimento di
                    # tag specifici nel file mm.
                    # Dal momento che queste opzioni servono a definire quali sono i file di input,
                    # leggo queste informazioni dai tag a valle di "DATASET".
                    ($DATASET->{$task}->{'xtc_file'} and $DATASET->{$task}->{'tpr_file'}) or do {
                        warn "\nW- undef input files for job <$tag> on <$task>, skipping...";
                        undef $cmd_string;
                        last CASEOF;
                    };
                    # Scrivo una stringa di comando di default...
                    $cmd_string .= sprintf(
                        "echo %s %s | g_rms -f %s -s %s",
                        $job->{'fit_group'},
                        $job->{'rmsd_group'},
                        $DATASET->{$task}->{'xtc_file'},
                        $DATASET->{$task}->{'tpr_file'}
                    );
                    # ...e vi aggiungo altre eventuali opzioni, definite da ulteriori subtag con una
                    # sintassi del tipo "opzione=[valore]" (es.: "tu=ns").
                    # Siccome io non sono tenuto a conoscere quante e quali opzioni siano valide su
                    # un comando sviluppato da altri, sta all'utente che crea il file mm conoscere
                    # quali sono le opzioni valide per lo specifico comando.
                    foreach my $opt (keys %{$job}) {
                        next if ($opt =~ m/_group/);
                        $cmd_string .= sprintf(
                            " -%s %s",
                            $opt,
                            $job->{$opt}
                        );
                    }
                    # Lo STDOUT/STDERR del comando lo re-indirizzo su un file di log comune, così
                    # da vedere se e come il job è andato a termine.
                    $cmd_string .= " >> $task.log 2>&1";
                    last CASEOF;
                };
                #
                # Prevedo che nel file mm l'utente voglia aggiunger altri job
                # (quali, ad es., i comandi 'g_rmsf' e 'g_sas').
                #
                # Di seguito si possono aggiungere quanti comandi se ne vogliono.
                # Ogni blocco di codice può essere scritto come nell'esempio sopra citato.
                # Ma potreste ad esempio reindirizzare l'hash specifico del job 'g_rms':
                #
                #   $mm2hash->{'WORKFLOW'}->{'JOBS'}->{'g_rms'}
                #
                # ad uno script esterno che si occupa di fare tutto lo sporco lavoro.
                /^g_rmsf$/ and do {
                    ($job->{'group'}) or do {
                        print "\nW- undef group for job <$tag> on <$task>, skipping...";
                        undef $cmd_string;
                        last CASEOF;
                    };
                    ($DATASET->{$task}->{'xtc_file'} and $DATASET->{$task}->{'tpr_file'}) or do {
                        print "\nW- undef input files for job <$tag> on <$task>, skipping...";
                        undef $cmd_string;
                        last CASEOF;
                    };
                    $cmd_string .= sprintf(
                        "echo %s | g_rmsf -f %s -s %s",
                        $job->{'group'},
                        $DATASET->{$task}->{'xtc_file'},
                        $DATASET->{$task}->{'tpr_file'}
                    );
                    foreach my $opt (keys %{$job}) {
                        next if ($opt =~ m/group/);
                        $cmd_string .= sprintf(
                            " -%s %s",
                            $opt,
                            $job->{$opt}
                        );
                    }
                    $cmd_string .= " >> $task.log 2>&1";
                    last CASEOF;
                };
                /^g_sas$/ and do {
                    ($job->{'in_group'} and $job->{'out_group'}) or do {
                        print "\nW- undef group for job <$tag> on <$task>, skipping...";
                        undef $cmd_string;
                        last CASEOF;
                    };
                    ($DATASET->{$task}->{'xtc_file'} and $DATASET->{$task}->{'tpr_file'}) or do {
                        print "\nW- undef input files for job <$tag> on <$task>, skipping...";
                        undef $cmd_string;
                        last CASEOF;
                    };
                    $cmd_string .= sprintf(
                        "echo %s %s | g_sas -f %s -s %s",
                        $job->{'in_group'},
                        $job->{'out_group'},
                        $DATASET->{$task}->{'xtc_file'},
                        $DATASET->{$task}->{'tpr_file'}
                    );
                    foreach my $opt (keys %{$job}) {
                        next if ($opt =~ m/_group/);
                        $cmd_string .= sprintf(
                            " -%s %s",
                            $opt,
                            $job->{$opt}
                        );
                    }
                    $cmd_string .= " >> $task.log 2>&1";
                    last CASEOF;
                };
            }
            # Qui raccolgo, per ogni set di dati, la lista dei job da lanciare
            # in un unico array
            push(@{$JOBS_LIST->{$task}}, $cmd_string) if ($cmd_string);
        }
    }
}

################################################################################
# Allestisco i singoli file sh (shell script) per ogni set di dati
use Cwd;
my $workdir = getcwd() . '/PATH_LINKS';
EDIT_SH: {
    mkdir $workdir;
    foreach my $job (keys %{$JOBS_LIST}) {
        # Nella working dir da cui ho lanciato questo script mi faccio una cartella
        # in cui creo una serie di link simbolici ai path di dove stanno i set di dati
        my $source_path = $DATASET->{$job}->{'path'};
        qx/cd $workdir; ln -s $source_path/;
        # Definisco un header generico per ogni file sh
        my $sh_content = <<END
#!/bin/sh

cd $source_path;

END
        ;
        # Accorpo nel file sh la lista dei job da lanciare
        $sh_content .= join(";\n", @{$JOBS_LIST->{$job}});
        # Scrivo nella cartella del set di dati specifico il file sh
        open SHFH, ">$source_path/WORKFLOW.SCRIPT.sh";
        print SHFH $sh_content;
        close SHFH;
    }
}

################################################################################
# Lancio gli script in parallelo
#
# Il programma definito in $sh_scheduler funziona in modo tale che cerca in tutte
# le sottocartelle di $workdir un file chiamato "WORKFLOW.SCRIPT.sh" (quello che
# contiene la lista dei job da lanciare); quindi lancia un thread indipendente
# per ogni file sh.
#
# Lo script che richiamo qui con $sh_scheduler butta sullo STDOUT un tabulato che
# man mano visualizza quali script sh sono in coda, quali sono già finiti e quali
# stanno attualmente girando.
#
# La variabile $nodes stabilisce il numero di threads da lanciare in simultanea,
# gli altri rimanenti verranno accodati.
#
# A questo punto vanno fatte un po' di considerazioni preliminari su come definire
# il numero esatto di threads simultanei; tipicamente $nodes varia da 1 a 2 volte
# il numero di core disponibili.
#
# Però occorre prestare maggiore attenzione nel caso si lancino comandi che
# richiamano conti che gireranno già parallelizzati e/o occupano quantità
# di memoria notevoli.
my $nodes = 3;
system("$sh_scheduler -d $workdir -n $nodes WORKFLOW.SCRIPT.sh");

exit;