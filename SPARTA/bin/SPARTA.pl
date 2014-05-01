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
use SPARTA::lib::Artemis; # modulo per l'inizializzazione del database
use SPARTA::lib::Leonidas; # modulo per la gestione generale delle modalità di analisi
use SPARTA::lib::FileIO; # modulo per leggere/scrivere su file
use Memory::Usage;

## GLOBS ##
# PATHS
our $workdir = getcwd();
our $SPARTA_path = qx/which SPARTA.pl/;
chomp $SPARTA_path;
$SPARTA_path =~ s/\/bin\/SPARTA\.pl$//;
our $addressbook = $SPARTA_path . '/data/addressbook.csv';
our $db_settings_file = $SPARTA_path . '/data/db_connect.txt';
our $sql_backup; # eventuale backup del DB
our $tmp_dir = $ENV{HOME} . '/.SPARTA';
our $log_path = $tmp_dir . '/SPARTA.log';
our $quote_file = $SPARTA_path . '/data/quotes.txt';
# OBJECTS
# i messaggi di errore andranno nel logfile definito da $log_path
our $artemis = SPARTA::lib::Artemis->new( 'errfile' => $log_path);
our $leonidas = SPARTA::lib::Leonidas->new( 'errfile' => $log_path);
our $logfile = SPARTA::lib::FileIO->new('filename' => $log_path);
# OTHERS
our $mode; # modalità di SPARTA
our $dataset = { }; # hash che descrive il mio dataset, dipende dal contenuto dell'addressbook
## SBLOG ##

USAGE: {
    print "*** SPARTA - a Structure based PAttern RecogniTion on Antibodies ***\n";
    
    my $options = { };
    use Getopt::Long;no warnings;
    GetOptions($options, 'help|h', 'bender', 'correlation', 'crossrefs', 'cluster', 'eneclust', 'enedist', 'enestat:f', 'fluclust', 'fludist', 'flustat:f', 'reinit', 'repair=s', 'rmsd', 'samba', 'test', 'dump');
    my $usage = <<END

*** SPARTA - release 12.09.alpha ***

OPTIONS
    
    -help|h         Print this help and exit.
    
MODES
    
  *** Database maintenance ***
    -dump           Make a dump of existing database.
    
    -reinit         Create a new database, overwriting the existing one.
    
    -repair         Restore the selected database, overwriting the existing one;
                    this mode require an SQL backup file of a previous DB:
                    (e.g.: "SPARTA.pl -repair backupDB.sql.tar.gz") 
    
  *** Analysis ***
    -bender         Performs statistics of the angles (means) and their 
                    variations (stddev) along the hinge regions of the chains of 
                    every system (apo/holo structures). Moreover, a two-way 
                    ANOVA will be carried out in order to find if the bending 
                    variations are significant between light/heavy chains and/or 
                    apo/holo forms.
    
    -cluster        Print a histogram of the structure clusters found for apo
                    and holo forms respectively according to g_cluster analysis.
    
    -correlation    For each system draw a scatter plot in order to correlate
                    energy and distance fluctuation matrices
    
    -crossrefs      Print a csv file in which all residues are mapped to the
                    common numbering schema.
    
    -eneclust       Cluster analysis of the structures of the dataset, based on 
                    the IERPs (see enedist mode) profile in apo and holo forms.
    
    -enedist        Distribution of the most relevant residues whose energetic 
                    contributions may be critical in the stabilization of the 
                    structures of the dataset. These residues map on recurrent 
                    positions scattered along each domain of the proteins; we 
                    define them as Interaction Energy Recurrent Positions 
                    (IERPs).
    
    -enestat        Performs statistical analyses about the distribution of the 
                    IERPs over the four domains of the Fab structures loaded in 
                    the dataset.
    
    -fluclust       Cluster analysis of the structures of the dataset, based on 
                    the RMRPs (see fludist mode) profile in apo and holo forms.
    
    -fludist        Distribution of the most relevant residues whose fluctuation 
                    contributions may be relevant on the structures of the 
                    dataset. These residues map on recurrent positions scattered 
                    along each domain of the proteins; we define them as 
                    Restrained Motion Recurrent Positions (RMRPs).
    
    -flustat        Performs statistical analyses about the distribution of the 
                    RMRPs over the four domains of the Fab structures loaded in 
                    the dataset.
    
    -rmsd           Print a boxplot of RMSD profiles of the structure dataset, 
                    for apo and holo forms respectively.

    
    -samba          Every system (APO/HOLO) of the dataset is scanned in order
                    to retrieve  the distance fluctuation values of all of the 
                    residue of Fab against the subset of those residue involved
                    in the binding (paratope)
    
  *** Development ***
    -test           Goto CHUNKTEST block (code testing).
    
INSTALLATION
    
    First of all you need to path the SPARTA package, update your [homedir]/.bashrc
    file by defining the Perl environment variables as in the following example:
    
    [...]
    export PATH=/home/dario/script/SPARTA/bin:\$PATH
    export PERL5LIB=\$PERL5LIB:/home/dario/script/SPARTA/lib
    [...]
    
    DEPENDECIES:
        - gnuplot 4.4 or higher
        - MUSTANG 3.2.1
        - MySQL client/server
        - Perl modules
            * DBI
            * Getopt::Long
            * LWP::UserAgent
            * Memory::Usage
            * Statistics::Basic
            * Statistics::Descriptive
            * Statistics::Normality
            * Statistics::TTest
            * threads::shared
            * Thread::Semaphore
        - R statistical software and packages
            * hopach (Bioconductor)
    
    SUGGESTED:
        - Perl modules
            * Tk::FastSplash
            * Tk::PNG
        - PyMol
    
NOTES
    
    SPARTA is developed in order to perform in multithread way. Please check
    that your installed Perl package is able to run multithread scripts.
    To do this type \$>perl -V and find a string alike "useithreads=define".
    If so that's alright, otherwise you need to compile another version of Perl
    with enabled the appropriate flags.

UPDATES
    
    *   2012-09-26: analysis mode
        implementation of correlation mode
    
PATCHES
    
END
    ;
    
    # ATTIVAZIONE OPZIONI
    if (exists $options->{'repair'}) { # acquisisco il file di backup
        $sql_backup = $options->{'repair'};
    }
    
    # SELEZIONE MODALITA'
    if (exists $options->{'help'}) {
        my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
        $mese = $mese+1;
        $mese = sprintf("%02d", $mese);
        $giom = sprintf("%02d", $giom);
        $ore = sprintf("%02d", $ore);
        $min = sprintf("%02d", $min);
        $sec = sprintf("%02d", $sec);
        my $date = ($anno+1900)."/$mese/$giom - $ore:$min:$sec"; 
        my $string = [ "\n\n\n*** SPARTA [$date] ***\n", "\nI- help splash < $date" ];
        $logfile->write('filedata' => $string, 'mode' => '>>'); 
        print $usage;
        goto FINE; }
    elsif (exists $options->{'bender'})     { $mode = 'bender'; }
    elsif (exists $options->{'cluster'})     { $mode = 'cluster'; }
    elsif (exists $options->{'correlation'})     { $mode = 'correlation'; }
    elsif (exists $options->{'crossrefs'})     { $mode = 'crossrefs'; }
    elsif (exists $options->{'dump'})     { $mode = 'dump'; }
    elsif (exists $options->{'eneclust'})     { $mode = 'eneclust'; }
    elsif (exists $options->{'enedist'})     { $mode = 'enedist'; }
    elsif (exists $options->{'enestat'})     { $mode = 'enestat'; }
    elsif (exists $options->{'fluclust'})     { $mode = 'fluclust'; }
    elsif (exists $options->{'fludist'})     { $mode = 'fludist'; }
    elsif (exists $options->{'flustat'})     { $mode = 'flustat'; }
    elsif (exists $options->{'reinit'})   { $mode = 'reinit'; }
    elsif (exists $options->{'repair'})     { $mode = 'repair'; }
    elsif (exists $options->{'rmsd'})     { $mode = 'rmsd'; }
    elsif (exists $options->{'samba'})     { $mode = 'samba'; }
    elsif (exists $options->{'test'})     { $mode = 'test'; }
    else { $mode = 'undef' }
}

INIT: { # inizializzazioni
    mkdir $tmp_dir unless (-e $tmp_dir); # creo una directory temporanea

    # scrivo l'header sul file di log
    my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
    $mese = $mese+1;
    $mese = sprintf("%02d", $mese);
    $giom = sprintf("%02d", $giom);
    $ore = sprintf("%02d", $ore);
    $min = sprintf("%02d", $min);
    $sec = sprintf("%02d", $sec);
    my $date = ($anno+1900)."/$mese/$giom - $ore:$min:$sec"; 
    my $string = [ "\n\n\n*** SPARTA [$date] ***\n" ];
    $logfile->write('filedata' => $string, 'mode' => '>>');
    
    # importo l'addressbook nella variabile globale $dataset, e iniziaòlizzo gli oggetti che ne necessitano
    addressbook(); 
    $leonidas->set_dataset($dataset);
    $artemis->set_dataset($dataset);
    
    # reperisco le credenziali di accesso al DB di SPARTA
    my $db_settings = SPARTA::lib::FileIO->new('filename' => $db_settings_file);
    my $content = $db_settings->read();
    while (my $row = shift @{$content}) {
        chomp $row;
        next unless ($row =~ /^\[/);
        my ($key, $value) = $row =~ m/^\[(\w+)\] ([\w\.]+)/;
        if ( $key =~ /host/) {
            $artemis->set_host($value);
            $leonidas->set_host($value);
        } elsif ( $key =~ /database/) { 
            $artemis->set_database($value);
            $leonidas->set_database($value);
        } elsif ( $key =~ /user/) { 
            $artemis->set_user($value);
            $leonidas->set_user($value);
        } elsif ( $key =~ /password/) {
            $artemis->set_password($value);
            $leonidas->set_password($value);
        }
    }
}

CORE: {
    # SPLASHSCREEN
    # lo lascio commentato: mi genera un segmentation fault, anche se poi il programma gira tranquillamente uguale
#     if ($mode !~ /(test|undef)/) {
#         my $pid = fork();
#         if ($pid != 0) {
#             Splash("/home/dario/script/SPARTA/data/splash.png"); # splashscreen
#         }
#     }
    
# ================================ ANALYSES ====================================
    $mode =~ /bender/ && do {
        $leonidas->hinge_flucts();
        goto FINE;
    };
    $mode =~ /cluster/ && do {
        $leonidas->cluster();
        goto FINE;
    };
    $mode =~ /correlation/ && do {
# i dati che reperisco in questo modo permettono di confrontare direttamente i 
# punti delle matrici energetiche e dinamiche. Ho visto che cosi facendo i dati
# sono debolmente correlati. Per energie molto negative o molto positive la 
# coordinazione delle fluttuazioni tende ad aumentare o a diminuire, 
# rispettivamente; d'altra parte, per energie di interazione prossime a zero i
# valori di fluttuazione sono completamente casuali.
        $leonidas->eneflu_correlation();
        goto FINE;
    };
    $mode =~ /crossrefs/ && do {
        $leonidas->crossrefs();
        goto FINE;
    };
    $mode =~ /eneclust/ && do {
        $leonidas->hotspot_cluster('ene');
        goto FINE;
    };
    $mode =~ /enedist/ && do {
        $leonidas->hotspots('ene'); # produco un .csv con la lista degli hotspots relativi a residui presenti in tutti i PDB; i valori tabulati sono estratti dalle tabelle decomp del DB
        $leonidas->rankproducts('ene', 100); # produco un csv con i rank product relativi ad ogni hotspot; RP è espresso in scala logaritmica (valori positivi sono hotspot tipici di APO, valori negativi sono relativi a HOLO, valori pari a 0 sono hotspots ubiquitari)
        $leonidas->rp_dist('ene', 0.05);
        goto FINE;
    };
    $mode =~ /enestat/ && do {
        $leonidas->hotspot_stats(0.05, 'KS', 'ene'); # specifico il Pvalue e il tipo di test statistico (KS = Kolmogorov-Smirnov; TT = Student T test)
        goto FINE;
    };
    $mode =~ /fluclust/ && do {
        $leonidas->hotspot_cluster('flu');
        goto FINE;
    };
    $mode =~ /fludist/ && do {
        $leonidas->hotspots('flu'); # produco un .csv con la lista degli hotspots relativi a residui presenti in tutti i PDB; i valori tabulati sono estratti dalle tabelle decomp del DB
        $leonidas->rankproducts('flu', 10000); # produco un csv con i rank product relativi ad ogni hotspot; RP è espresso in scala logaritmica (valori positivi sono hotspot tipici di APO, valori negativi sono relativi a HOLO, valori pari a 0 sono hotspots ubiquitari)
        $leonidas->rp_dist('flu', 0.05);
        goto FINE;
    };
    $mode =~ /flustat/ && do {
        $leonidas->hotspot_stats(0.05, 'KS', 'flu'); # specifico il Pvalue e il tipo di test statistico (KS = Kolmogorov-Smirnov; TT = Student T test)
        goto FINE;
    };
    $mode =~ /rmsd/ && do { 
        $leonidas->rmsd();
        goto FINE;
    };
    $mode =~ /samba/ && do { 
        $leonidas->samba();
        goto FINE;
    };
# ============================= DB MAINTENANCE =================================
    $mode =~ /reinit/ && do {
        printf("\nW- SPARTA will drop every database called \"%s\" on %s.\nDo you really want to proceed? [y/N]", $artemis->get_database(), $artemis->get_host());
        my $answer = <STDIN>;
        goto FINE unless $answer;
        goto FINE if ($answer !~ /^y$/i);
        message(sprintf("\nI- creating database [%s] on [%s]...", $artemis->get_database, $artemis->get_host));
        $artemis->new_database();
        $artemis->rcsb();               # info generali sui miei PDB
        $artemis->upload_seqs();        # sequenze amminoacidiche
        $artemis->abnumpdb();           # sequenze indicizzate secondo abnumpdb
        $artemis->upload_structure();   # annotazioni strutturali (necessita delle tabelle costruite sopra) 
        $artemis->pdbsum();             # contatti prot-prot annotati su PDBsum
        $artemis->resdiff();            # crossrefs tra i resid dei pdb originali e quelli processati
        $artemis->rmsd();               # profili di RMSD
        $artemis->clusters();           # cluster analysis (metodo 'gromos', cutoff 0.2)
        $artemis->fluctuations();       # profili di RMSF
        $artemis->refschema();          # numbering schema universale
        $artemis->enedist();            # distribuzione delle energie di interazione
        $artemis->enematrix();          # matrici delle energie di interazione
        $artemis->enedecomp(200);       # energy decomposition analysis (non voglio filtrare per la matrice dei contatti, quindi uso un cutoff arbitrariamente alto di 200A)
        $artemis->fludist();            # distribuzione delle fluttuazioni
        $artemis->flumatrix();          # matrici di local distance fluctuation (v. EMMA.pl)
        $artemis->fludecomp(200);       # decomposition analysis sui dati di distance fluctuation (non voglio filtrare per la matrice dei contatti, quindi uso un cutoff arbitrariamente alto di 200A)
        $artemis->annotation();         # annotazioni strutturali
        $artemis->hinges();             # angoli tra i domini Ig
        goto FINE;
    };
    $mode =~ /dump/ && do {
        backup_db();
        goto FINE;
    };
    $mode =~ /repair/ && do {
        INPUT_CHECK: {
            error(sprintf("\nE- [SPARTA] [%s] file not found\n\t", $sql_backup))
                unless (-e $sql_backup);
        }
        
        printf("\nW- SPARTA will drop every database called \"%s\" on %s.\nDo you really want to proceed? [y/N]", $artemis->get_database(), $artemis->get_host());
        my $answer = <STDIN>;
        goto FINE unless $answer;
        goto FINE if ($answer !~ /^y$/i);
        
        message(sprintf("\nI- extracting SQL from [%s]...", $sql_backup));
        my $cmdline = sprintf("/bin/tar Oxzvf %s > %s/foobarbaz.sql", $sql_backup, $workdir);
        system $cmdline;
        $artemis->new_database();
        message("\nI- uploading SQL statements...");
        $cmdline = sprintf("/usr/bin/mysql -u %s -h %s %s -p%s < %s/foobarbaz.sql;", $artemis->get_user(), $artemis->get_host(), $artemis->get_database, $artemis->get_password(), $workdir);
        system $cmdline;
        unlink "$workdir/foobarbaz.sql";
        goto FINE;
    };
# ==============================================================================
    $mode =~ /test/ && do { # testing
        goto CHUNKTEST;
    };
    $mode =~ /.*/ && do { # comportamento predefinito
        message("\nI- nothing to do");
        goto FINE;
    };
}

CHUNKTEST: {
    print "\n\n*** CHUNKTEST ***\n";
    my $mu = Memory::Usage->new();
    $mu->record('start'); # monitoraggio memoria
# ===========================CODICE_DA_TESTARE==================================
    
    print "\nHELLO WORLD!";
    
# ==============================================================================
    $mu->record('stop'); # monitoraggio memoria
    # Report finale:
    my $performance = $mu->report();
    my $memreport = <<END


--- MEM PERFORMANCE (in kB)---
time....timestamp (in seconds since epoch)
vsz.....virtual memory size
rss.....resident set size
shared..shared memory size
code....text size
data....data and stack size

$performance
END
    ;
#     print $memreport;
    print "\n\n*** TSETKNUHC ***";
}

FINE: {
    print "\n\n" . quotes() . "\n*** ATRAPS ***\n";
    
    # scrivo il trailer sul file di log
    my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
    $mese = $mese+1;
    $mese = sprintf("%02d", $mese);
    $giom = sprintf("%02d", $giom);
    $ore = sprintf("%02d", $ore);
    $min = sprintf("%02d", $min);
    $sec = sprintf("%02d", $sec);
    my $date = ($anno+1900)."/$mese/$giom - $ore:$min:$sec";  
    my $string = [ "\n\n*** ATRAPS [$date] ***\n" ];
    $logfile->write('filedata' => $string, 'mode' => '>>');
    
    exit;
}

sub addressbook {
# L'addressbook è un file tabulato in formato CSV in cui sono contenute le informazioni
# di base per ricostruire il dataset su cui si sta lavorando (es. dove si trovano i file PDB).
# Questa sub si occupa di creare una copia interna dell'addressbook (un hashref
# per intenderci), inizializzando la variabile globale $dataset

    message(sprintf("\nI- importing dataset info from [%s]...", $addressbook));
    my $fileobj = SPARTA::lib::FileIO->new();
    my $content = $fileobj->read($addressbook);
    
    # estraggo i nomi dei campi
    my $header = shift @{$content};
    chomp $header;
    my @fields = split (";", $header);
    shift @fields;
    
    # estraggo i record
    foreach my $row (@{$content}) {
        chomp $row;
        my @record = split (";", $row);
        my $primary_key = shift @record;
        $dataset->{$primary_key} = { };
        my $index = 0;
        while (my $cell = shift @record) {
            $dataset->{$primary_key}->{$fields[$index]} = $cell;
            $index++;
        }
    }
    
    return 1;
}

sub backup_db {
# Fa un dump del database. Butta fuori uno script SQL che viene compresso in un file targz.

    message(sprintf("\nI- dumping database [%s] on [%s]...", $artemis->get_database, $artemis->get_host));
    my $filepath = $artemis->db_dump();
    message(sprintf("\nI- database dumped onto [%s]", $filepath));
    
    return 1;
}

sub error {
# Stampa i messaggi di errore su terminale e contemporaneamente sul file di log definito
# dalla variabile globale $log_path
    my ($string) = @_;
    
    print $string;
    $logfile->write('filedata' => [ $string ], 'mode' => '>>');
    
    die;
}

sub message {
# Stampa i messaggi su terminale e contemporaneamente sul file di log definito
# dalla variabile globale $log_path

    my ($string) = @_;
    
    print $string;
    
    # scrivo il trailer sul file di log
    my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
    $mese = $mese+1;
    $mese = sprintf("%02d", $mese);
    $giom = sprintf("%02d", $giom);
    $ore = sprintf("%02d", $ore);
    $min = sprintf("%02d", $min);
    $sec = sprintf("%02d", $sec);
    my $date = ($anno+1900)."/$mese/$giom - $ore:$min:$sec";
    $logfile->write('filedata' => [ $string . " < $date"], 'mode' => '>>');
    
    return 1;
}

sub quotes {
# eheheh...

    my $sep = $/;
    $/ = ">>\n";
    open(CITA, "<$quote_file") or return "<< >>";
    my @quotes = <CITA>;
    close CITA;
    my $tot = scalar @quotes;
    $/ = $sep;
    
    return $quotes[int(rand($tot))];
}

sub Splash {
    use Tk::PNG;
    use Tk::FastSplash;
    
    my ($imagefile) = @_;
    
    unless (-e $imagefile) {
        message("\nW- no splash");
    };
    
    my $splash = Tk::FastSplash->Show($imagefile, 600, 450, "SPARTA - a Structure based PAttern RecogniTion on Antibodies", 1); 
    sleep 2;
    
    $splash->Destroy if $splash;
}