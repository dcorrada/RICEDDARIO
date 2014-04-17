package RICEDDARIO::lib::PBS_manager::Scheduler;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| =1;

use lib $ENV{HOME};

use strict;
use warnings;
use Carp;
use Cwd;
use RICEDDARIO::lib::FileIO;
use RICEDDARIO::lib::Clock;
our $AUTOLOAD;



# Variabili e metodi interni alla classe
# Definizione degli attributi della classe
# chiave        -> nome dell'attributo
# valore [0]    -> valore di default
# valore [1]    -> permessi di accesso all'attributo
#                  (lettura, modifica...)

{
    # STRUTTURA DATI
    my %_attribute_properties = (
        # questo è il numero massimo di job che possono essere eseguiti contemporanamente
        _max_jobs            => [ '15',   'read.write.'],  
        # se la coda è piena, devo aspettare questo tempo
        _queue_time          => [ '60',   'read.write.'],
        # indica il numero massimo di accessi al server prima di chiudere lo script
        _server_fail         => [ '10',    'read.write.'],
        # messaggio di errore generico
        _exception           => [ '',   'read.'],


    );


# Ritorna la lista degli attributi
    sub _all_attributes {
        return keys %_attribute_properties;
    }

# Verifica gli accessi dell'attributo
    sub _permissions {
        my($self, $attribute, $permissions) = @_;
        return ($_attribute_properties{$attribute}[1] =~ /$permissions/);
    }
    
# Ritorna il valore di default dell'attributo
    sub _attribute_default {
    	my($self, $attribute) = @_;
    	return $_attribute_properties{$attribute}[0];
    }
    
# Verifica che le chiavi di hash passate come argomento corrispondano
# agli attributi della classe
    sub _check_attributes {
        my ($self, @arg_list) = @_;
        my @attribute_list = _all_attributes();
        my $attributes_not_found = 0;
        
        foreach my $arg (@arg_list) {
            unless (exists $self->{'_'.$arg}) {
                print "\n*** Attributo _$arg non previsto\n";
                $attributes_not_found++;
            }
        }
        return $attributes_not_found;
    }

}


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
                print "\n*** Attributo $attribute disponibile in sola lettura\n";
                $self->{$attribute} = $self->_attribute_default($attribute);
            }
        # ...o con il valore di default altrimenti
        } else {
            $self->{$attribute} = $self->_attribute_default($attribute);
        }
    }
    
    # verifico se sono stati chiamati degli attributi che non sono previsti in questa classe
    $self->_check_attributes(keys %arg);
    
    return $self;
}

# Gestisce metodi non esplicitamente definiti nella classe
sub AUTOLOAD {
    # disabilito i messaggi di warnings derivanti da un mancato
    # uso di $AUTOLOAD
    no warnings;
    
    my ($self, $newvalue) = @_;
    
    # Se viene chiamato qualche metodo non definito...
    # analizza il nome del metodo, es. con "get_filename":
    # $operation = 'get' e $attribute = '_filename'
    #
    # ATTENZIONE: la sintassi nel pattern matching di $AUTOLOAD dipende dalla sintassi
    # data nel package. Ad esempio nel caso volessi individuare il package di questa
    # classe ("my_mir::UCSC::Fasta_Table") dovrei anteporre "\w+::\w+::\w+::" alla
    # stringa "([a-zA-Z0-9]+)_(\w+)$".
    my ($operation, $attribute) = $AUTOLOAD =~ /^\w+::\w+::\w+::([a-zA-Z0-9]+)_(\w+)$/;
    
    if ($operation, $attribute) {
        $self->_check_attributes($attribute) and croak("\nMetodo $AUTOLOAD non previsto");
        $attribute = '_'.$attribute;
        
        # metodi per la lettura di attributi
        # ATTENZIONE: se l'attributo in questione NON è uno scalare 
        #             viene ritornata una REF del dato e NON il
        #             dato stesso
        if ($operation eq 'get') {
            # controlla che l'attributo abbia il permesso in lettura
            if ($self->_permissions($attribute, 'read')) {
                return $self->{$attribute};
            } else {
                print "\nAttributo $attribute senza accesso in lettura";
            }
        
        # metodi per la scrittura di attributi
        # ATTENZIONE: se l'attributo in questione NON è uno scalare 
        #             occorre passare una REF del dato e NON il
        #             dato stesso
        } elsif ($operation eq 'set') {
            # controlla che l'attributo abbia il permesso in scrittura
            if ($self->_permissions($attribute, 'write')) {
                $self->{$attribute} = $newvalue;
            } else {
                print "\nAttributo $attribute senza accesso in scrittura";
            }
            
        } else {
            croak("\nMetodo $AUTOLOAD non previsto");
        }
    } else {
        croak("\nMetodo $AUTOLOAD non previsto");
    }
    use warnings;
}

# Definisce come si comporta l'oggetto chiamato una volta uscito dal
# proprio scope
sub DESTROY {
    my ($self) = @_;
    
}



# produce una stringa contenente il comando esteso per lanciare RNAhybrid
#
# %opzioni = ( path    => $arg1, OPZIONALE path del programma di predizione 'RNAhybrid'
#              t       => $arg2, OBBLIGATORIO fasta file containing the UTRs to be scanned
#              q       => $arg3, OBBLIGATORIO fasta file containing the microRNA sequences
#              [other] => $argn, OPZIONALE tutte le altre opzioni, consultare il file 'RNAhybrid'
#            );
sub _rnahybrid_string {
    my ($self, %arg) = @_;
    
    # specifico le opzioni necessarie senza le quali miRanda non funzionerebbe
    foreach my $opt ('t', 'q') {
        unless (exists $arg{$opt}) {
            $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->_pita_string(t => arg1, q => arg2)

END
            ;
            croak $self->get_exception();
        }
    }
    
# Altero alcuni parametri di default se non specificamente chiamati
    $arg{p} = '0.03' unless (exists $arg{p}); # valore soglia minimo di pvalue
    $arg{f} = '2,7' unless (exists $arg{f}); # forzo un annealing per la regione da 2 a 7 sul mir (privilegio i complessi 5'dominanti)
    $arg{b} = '5' unless (exists $arg{b}); # numero max di binding site da cercare
    $arg{s} = '3utr_human' unless (exists $arg{s}); # per stimare parametri di distribuzione su cui calcolare il p-value
    $arg{m} = '15000' unless (exists $arg{m}); # lunghezza massima dell'utr 
                                                # (su UTRresource la max 3'UTR umana è 12584bp e 11822bp x la murina)
    

    
    my $command_line = 'time ';
    
    # inserisco il path di RNAhybrid nella stringa
    if (exists $arg{path}) {
        $command_line .= $arg{path} . '/RNAhybrid';
    } else {
        $command_line .= 'RNAhybrid';
    }

    # accodo tutte le opzioni alla stringa
    foreach my $opt (keys %arg) {
        unless ($opt eq 'path') {
            $command_line .= " -$opt $arg{$opt}";
        }
    }
    return $command_line;
}




# produce una stringa contenente il comando esteso per lanciare MIRANDA
#
# %opzioni = ( path    => $arg1, OPZIONALE path del programma di predizione 'miranda'
#              utr     => $arg2, OBBLIGATORIO fasta file containing the UTRs to be scanned
#              mir     => $arg3, OBBLIGATORIO fasta file containing the microRNA sequences
#              [other] => $argn, OPZIONALE tutte le altre opzioni, consultare il file 'miranda'
#            );
sub _miranda_string {
    my ($self, %arg) = @_;
    
    # specifico le opzioni necessarie senza le quali miRanda non funzionerebbe
    foreach my $opt ('utr', 'mir') {
        unless (exists $arg{$opt}) {
            $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->_pita_string(utr => arg1, mir => arg2)

END
            ;
            croak $self->get_exception();
        }
    }
    
# Altero alcuni parametri di default se non specificamente chiamati
# (secondo i parametri usati nelle release note di Gennaio 2008 su microrna.org)
    $arg{sc} = '140' unless (exists $arg{sc}); # valore soglia minimo di score
    $arg{en} = '-20' unless (exists $arg{en}); # energy, valore soglia di stabilità termodinamica
    $arg{go} = '-9' unless (exists $arg{go}); # gap opening penalty
    $arg{ge} = '-4' unless (exists $arg{ge}); # gap extend penalty
    $arg{scale} = '4' unless (exists $arg{scale}); # fattore di scala per privilegiare lo score con allineamenti migliori sui primi 10 nucleotidi

    
    my $command_line = 'time ';
    
    # inserisco il path di miRanda nella stringa
    if (exists $arg{path}) {
        $command_line .= $arg{path} . '/miranda';
    } else {
        $command_line .= 'miranda';
    }

    $command_line .= " $arg{mir} $arg{utr}";
    
    # accodo tutte le opzioni alla stringa
    foreach my $opt (keys %arg) {
        next if ($opt =~ m/^path|utr|mir$/);
        $command_line .= " -$opt $arg{$opt}";
    }
    return $command_line;
}


# produce una stringa contenente il comando esteso per lanciare PITA
#
# %opzioni = ( path    => $arg1, OPZIONALE path del programma di predizione 'pita_prediction.pl'
#              utr     => $arg2, OBBLIGATORIO fasta file containing the UTRs to be scanned
#              mir     => $arg3, OBBLIGATORIO fasta file containing the microRNA sequences
#              prefix  => $arg4, OBBLIGATORIO Add the string as a prefix to the output files (pita_results.tab and ext_utr.stab)
#              [other] => $argn, OPZIONALE tutte le altre opzioni, consultare il file 'pita_prediction.pl'
#            );
sub _pita_string {
    my ($self, %arg) = @_;
    
    # specifico le opzioni necessarie senza le quali PITA non funzionerebbe
    foreach my $opt ('utr', 'mir') {
        unless (exists $arg{$opt}) {
            $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->_pita_string(utr => arg1, mir => arg2, prefix => arg3)

END
            ;
            croak $self->get_exception();
        }
    }
    
    my $command_line = 'time ';
    
    # inserisco il path di pita nella stringa
    if (exists $arg{path}) {
        $command_line .= $arg{path} . '/pita_prediction.pl';
    } else {
        $command_line .= 'pita_prediction.pl';
    }
    
    # accodo tutte le opzioni alla stringa
    foreach my $opt (keys %arg) {
        unless ($opt eq 'path') {
            $command_line .= " -$opt $arg{$opt}";
        }
    }
    return $command_line;
}

# Ritorna un array con il contenuto di un file PBS.
#
# %opzioni = ( jobname => $arg1, OBBLIGATORIO nome del job
#              script  => $arg2, OBBLIGATORIO le righe di script per il quale girerà il job
#              stderr  => $arg3, OPZIONALE nome file standard error
#              stdout  => $arg4, OPZIONALE nome file standard output
#              cwd     => $arg5, OPZIONALE directory di lavoro per il job, di default è quella corrente
#              queue   => $arg6, OPZIONALE coda dove eseguire il job, di default è 'projects'
#              node    => $arg7, OPZIONALE numero di nodi da usare (default 1)
#              ppn     => $arg8, OPZIONALE numero di processori per nodo (default 1)
#              mem     => $arg9, OPZIONALE quanta RAM utilizzare (es '1024mb')
#            );
sub edit_PBS_file {
    my ($self, %arg) = @_;
    
    # array contenente le singole righe del file PBS
    my @file_content = ('#!/bin/sh', "\n#PBS -V", '#PBS -m a',);

    # specifico le opzioni necessarie per il corretto editing del file
    foreach my $opt ('jobname', 'script') {
        unless (exists $arg{$opt}) {
            $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->edit_PBS_file(jobname => \$arg1, script => \$arg2)

END
            ;
            croak $self->get_exception();
        }
    }
    
    push @file_content, "#PBS -N $arg{jobname}";

    $arg{stderr}?
        push @file_content, "#PBS -e $arg{stderr}" : push @file_content, "#PBS -e $arg{jobname}.e";
    $arg{stdout}?
        push @file_content, "#PBS -o $arg{stdout}" : push @file_content, "#PBS -o $arg{jobname}.o";
    $arg{cwd}?
        push @file_content, "#PBS -d $arg{cwd}" : push @file_content, "#PBS -d ".getcwd;
    $arg{queue}?
        push @file_content, "#PBS -d $arg{queue}" : push @file_content, "#PBS -q projects";
    $arg{nodes} or $arg{nodes} = '1';$arg{ppn} or $arg{ppn} = '1';
    push @file_content, "#PBS -l nodes=$arg{nodes}:ppn=$arg{ppn}";
    push (@file_content, "#PBS -l mem=$arg{mem}") if $arg{mem};
    
    push (@file_content, "\n".'echo -e "\nJobID --> $PBS_JOBID  ( $PBS_JOBNAME )\nlanciato sul nodo $HOSTNAME\nCoda $PBS_QUEUE eseguita su $PBS_O_HOST" >>  ~/PBS_manager_submissions.log');
    push @file_content, "\n$arg{script}";
    
    return @file_content;

}

# Data una coppia di file FASTA mirna.fa/utr.fa crea un file PBS per lanciare miRAnda
#
# %opzioni = ( utr => $arg1, OBBLIGATORIO fasta file containing the UTRs to be scanned
#              mir => $arg2, OBBLIGATORIO fasta file containing the microRNA sequences
#            );
# 
# ATTENZIONE: sarebbe più corretto corredare utr e mir con il percorso assoluto e non solo il nome del file
sub write_miranda_job {
    my ($self, %arg) = @_;
    my %params = (  utr_file => '',
                    mir_file => '',
                    jobname  => '',
                 );
    
    # specifico le opzioni necessarie senza le quali PITA non funzionerebbe
    foreach my $opt ('mir', 'utr') {
        if (not(exists $arg{$opt})) {
            $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->write_miranda_job(utr => \$arg1, mir => \$arg2)

END
            ;
            croak $self->get_exception();
        # verifico che il nome dei file sia completo di path
        } elsif ($arg{$opt} =~ /\//g) {
            $params{$opt.'_file'} = $arg{$opt};
        } else {
            $params{$opt.'_file'} = getcwd.'/'.$arg{$opt};
        }
        
        # definiosco il nome del job
        my ($name) = $arg{$opt} =~ /\/?([\w\.-]+)$/g;
        $name =~ s/\.fa//g;
        $params{jobname} .= $name;
    }
    
    my @file_content = $self->edit_PBS_file( 
                                    jobname =>  $params{jobname},
                                    script =>   $self->_miranda_string(
                                                                utr    => $params{utr_file},
                                                                mir    => $params{mir_file},
                                                                out => getcwd.'/'.$params{jobname}.'.log',
                                                                ),
                                    );
    my $file_obj = RICEDDARIO::lib::FileIO->new();
    
    for (my $counter = 0; $counter < scalar(@file_content); $counter++) {
        $file_content[$counter] .= "\n";
    }
    $file_obj->write(filename => $params{jobname}.'.pbs', filedata => \@file_content);
    
    return @file_content;
}

# Data una coppia di file FASTA mirna.fa/utr.fa crea un file PBS per lanciare PITA
#
# %opzioni = ( utr => $arg1, OBBLIGATORIO fasta file containing the UTRs to be scanned
#              mir => $arg2, OBBLIGATORIO fasta file containing the microRNA sequences
#            );
# 
# ATTENZIONE: sarebbe più corretto corredare utr e mir con il percorso assoluto e non solo il nome del file
sub write_pita_job {
    my ($self, %arg) = @_;
    my %params = (  utr_file => '',
                    mir_file => '',
                    jobname  => '',
                 );
    
    # specifico le opzioni necessarie senza le quali miRanda non funzionerebbe
    foreach my $opt ('mir', 'utr') {
        if (not(exists $arg{$opt})) {
            $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->write_pita_job(utr => \$arg1, mir => \$arg2)

END
            ;
            croak $self->get_exception();
        # verifico che il nome dei file sia completo di path
        } elsif ($arg{$opt} =~ /\//g) {
            $params{$opt.'_file'} = $arg{$opt};
        } else {
            $params{$opt.'_file'} = getcwd.'/'.$arg{$opt};
        }
        
        # definisco il nome del job
        my ($name) = $arg{$opt} =~ /\/?([\w\.-]+)$/g;
        $name =~ s/\.fa//g;
        $params{jobname} .= $name;
    }
    
    my @file_content = $self->edit_PBS_file( 
                                    jobname =>  $params{jobname},
                                    script =>   $self->_pita_string(
                                                                utr    => $params{utr_file},
                                                                mir    => $params{mir_file},
                                                                prefix => getcwd.'/'.$params{jobname},
                                                                ),
                                    );
    my $file_obj = RICEDDARIO::lib::FileIO->new();
    
    for (my $counter = 0; $counter < scalar(@file_content); $counter++) {
        $file_content[$counter] .= "\n";
    }
    $file_obj->write(filename => $params{jobname}.'.pbs', filedata => \@file_content);
    
    return @file_content;
}

# Data una coppia di file FASTA mirna.fa/utr.fa crea un file PBS per lanciare RNAhybrid
#
# %opzioni = ( utr => $arg1, OBBLIGATORIO fasta file containing the UTRs to be scanned
#              mir => $arg2, OBBLIGATORIO fasta file containing the microRNA sequences
#            );
# 
# ATTENZIONE: sarebbe più corretto corredare utr e mir con il percorso assoluto e non solo il nome del file
sub write_rnahybrid_job {
    my ($self, %arg) = @_;
    my %params = (  utr_file => '',
                    mir_file => '',
                    jobname  => '',
                 );
    
    # specifico le opzioni necessarie senza le quali miRanda non funzionerebbe
    foreach my $opt ('mir', 'utr') {
        if (not(exists $arg{$opt})) {
            $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->write_rnahybrid_job(utr => \$arg1, mir => \$arg2)

END
            ;
            croak $self->get_exception();
        # verifico che il nome dei file sia completo di path
        } elsif ($arg{$opt} =~ /\//g) {
            $params{$opt.'_file'} = $arg{$opt};
        } else {
            $params{$opt.'_file'} = getcwd.'/'.$arg{$opt};
        }
        
        # definisco il nome del job
        my ($name) = $arg{$opt} =~ /\/?([\w\.-]+)$/g;
        $name =~ s/\.fa//g;
        $params{jobname} .= $name;
    }
    
    my @file_content = $self->edit_PBS_file( 
                                    jobname =>  $params{jobname},
                                    script =>   $self->_rnahybrid_string(
                                                                t    => $params{utr_file},
                                                                q    => $params{mir_file},
                                                                ),
                                    );
    my $file_obj = RICEDDARIO::lib::FileIO->new();
    
    for (my $counter = 0; $counter < scalar(@file_content); $counter++) {
        $file_content[$counter] .= "\n";
    }
    $file_obj->write(filename => $params{jobname}.'.pbs', filedata => \@file_content);
    
    return @file_content;
}

# verifica il numero di job in coda, se è inferiore a $self->{_max_jobs} ritorna 1,
# altrimenti ritorna 0
#
sub qstat_status {
    my ($self) = @_;
    
    my $qstat_output;$self->{_exception} = '';
    my $fails = 0; # numero di volte in cui l'accesso al server fallisce
    my $clock = 'RICEDDARIO::lib::Clock';
    
    while (1) {
        $qstat_output = qx/qstat 2>&1/;
        
        if ($fails > $self->{_server_fail}) {
            $self->{_exception} .= "\noltre $self->{_server_fail} accessi falliti!\n";
            croak "$self->{_exception}";
        
        # verifico la presenza di un mess di errore noto
        } elsif ($qstat_output =~ /No Permission/g) {
            $self->{_exception} .= $clock->date . $qstat_output;
            print $clock->date . $qstat_output . "\n";
            # se rileva il mess di errore incrementa il numero di tentativi a vuoto ($fails), attende un lasso di tempo (sleep) e riprende il ciclo
            $fails++;sleep $self->{_queue_time};next;
            
        # gestisco il normale output di qstat: ritorna 1 se non qstat presenta
        # un numero di job < $self->{_max_jobs}, 0 altrimenti
        } elsif (($qstat_output =~ /^Job id/g)||(!$qstat_output)) {
            if ($qstat_output) {
                my (@content) = split /\n/, $qstat_output;
                ((scalar(@content)-2) < $self->{_max_jobs})? return 1 : return 0;
            } else { return 1 }
        
        # gestisco mess d'errore non previsti
        } else {
            $self->{_exception} = "messaggio di QSTAT non previsto: $qstat_output\n";
            # sleep $self->{_queue_time};next;
            croak "$self->{_exception}";
        }
        
        # ri-inizializzo il counter per i mess di errore
        $self->{_exception} = '';$fails = 0;
    }
    
}

# un metodo per sottomettere i SINGOLI job
# è OBBLIGATORIO specificare il nome del file contenente il job
sub submit_job {
    my ($self, $jobname) = @_;
    
    
    unless (defined $jobname) {
        $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->submit_job($jobname)

END
        ;
        croak $self->get_exception();
    }
    
    my $qsub_output;$self->{_exception} = '';
    my $fails = 0; # numero di volte in cui l'accesso al server fallisce
    my $clock = 'RICEDDARIO::lib::Clock';
    
    while (1) {
        $qsub_output = qx/qsub $jobname 2>&1/;
        
        if ($fails > $self->{_server_fail}) {
            $self->{_exception} .= "\noltre $self->{_server_fail} accessi falliti!\n";
            croak "$self->{_exception}";
        
        # verifico la presenza di un mess di errore noto
        } elsif ($qsub_output =~ /No Permission/g) {
            $self->{_exception} .= $clock->date . $qsub_output;
            print $clock->date . $qsub_output . "\n";
            # se rileva il mess di errore incrementa il numero di tentativi a vuoto ($fails), attende un lasso di tempo (sleep) e riprende il ciclo
            $fails++;sleep $self->{_queue_time};next;
            
        # gestisco il normale output di qstat: ritorna 1 se non qstat presenta
        # un numero di job < $self->{_max_jobs}, 0 altrimenti
        } elsif ($qsub_output =~ /^\d+\.michelangelo\.cilea\.it/g) {
            print "job successfully submitted!";
            return 1;
        
        # gestisco mess d'errore non previsti
        } else {
            $self->{_exception} = "messaggio di QSUB non previsto: $qsub_output\n";
            # sleep $self->{_queue_time};next;
            croak "$self->{_exception}";
        }
        
        # ri-inizializzo il counter per i mess di errore
        $self->{_exception} = '';$fails = 0;
    }
    
}



1;
