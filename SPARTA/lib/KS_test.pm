package SPARTA::lib::KS_test;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| =1;

use lib $ENV{HOME};

use strict;
use warnings;
use Carp;
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
        # distribuzioni osservate
        _dist_obs_1            => [ [ ],   'read.write.'],
        _dist_obs_2            => [ [ ],   'read.write.'],
        # numero di osservazioni per ciascuna distribuzione
        _n_obs_1               => [ '',    'read.'],
        _n_obs_2               => [ '',    'read.'],
        # distribuzioni delle frequenze relative
        _dist_rel_freq_1       => [ [ ],   'read.'],
        _dist_rel_freq_2       => [ [ ],   'read.'],
        # distribuzioni cumulate
        _dist_cumul_1          => [ [ ],   'read.'],
        _dist_cumul_2          => [ [ ],   'read.'],
        # distribuzione delle differenze tra le cumulate
        _dist_D                => [ [ ],   'read.'],     
        # P-value per il calcolo del valore critico J
        _pvalue                => [ '0.05',    'read.write.'],
        # definisce se eseguire il test a una coda (oneside) o a due code (twoside)
        _mode                  => [ 'twoside', 'read.write.'],
        
        # valori di output del test (rispettivamente differenza massima e valore critico)
        _D_max                 => [ '',   'read.'], 
        _J_value               => [ '',   'read.'], 
        
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


# per ogni distribuzione conta il numero di osservazioni;
# $distrib è un ref all'array contenente la distribuzione da valutare
sub _count_obs {
    my ($self, $ref_distrib) = @_;
    
    # specifico le opzioni necessarie per il corretto editing del file
    unless ($ref_distrib) {
        $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->_count_obs(\\\@distribuzione_osservata)

END
        ;
        croak $self->get_exception();
    }
    
    my @distrib = @$ref_distrib;
    my $counter = 0;

    foreach my $value (@distrib) {
        $counter += $value if $value;
    }
    
    return $counter;
}

# genera una distribuzione delle frequenze relative
sub _build_dist_rel_freq {
    my ($self, %arg) = @_;
    
    # specifico le opzioni necessarie per il corretto editing del file
    unless (exists $arg{'dist'}) {
        $self->{_exception} = <<END
---
Parametri mancanti, sintassi:
\$self->_build_dist_rel_freq( dist => \\\@distribuzione_osservata,
                            [count => \$num_osservazioni])

END
        ;
        croak $self->get_exception();
    }
    
    # conto il numero di osservazioni se non viene esplicitato alla chiamata della sub
    unless (exists $arg{'count'}) {
       $arg{'count'} = $self->_count_obs($arg{'dist'});
    }
    
    my $dist_rel_freq = [ ];
    foreach my $obs (@{$arg{'dist'}}) {
        # calcolo la frequenza relativa per ogni classe della distribuzione osservata...
        my $value = $obs / $arg{'count'};
        # ...e la aggiungo all'array che mi rappresentera' la distribuzione delle frequenze
        push @$dist_rel_freq, sprintf ("%.4f", $value);
    }
    
    return $dist_rel_freq;

}

# genera una distribuzione cumulata
sub _build_dist_cumul {
    my ($self, $ref_distrib) = @_;
    
    # specifico le opzioni necessarie per il corretto editing del file
    unless ($ref_distrib) {
        $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->_count_obs(\\\@distribuzione_freq_relative)

END
        ;
        croak $self->get_exception();
    }
    
    my ($dist_cumul, $index) = ([ 0 , ], 0);
    foreach my $freq (@$ref_distrib) {
        $index++;
        $$dist_cumul[$index] = sprintf ("%.4f", $$dist_cumul[$index-1] + $freq);
    }
    shift @$dist_cumul;
    
    return $dist_cumul;
}

# genera una distribuzione delle differeze tra due distribuzioni
sub _build_dist_diff {
    my ($self, $dist_1, $dist_2) = @_;
    
    # specifico le opzioni necessarie per il corretto editing del file
    unless ($dist_1 && $dist_2) {
        $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->_build_dist_diff(\\\@distribuzione_A, \\\@distribuzione_B)

END
        ;
        croak $self->get_exception();
    }
    
    unless (scalar @$dist_1 == scalar @$dist_2) {
        $self->{_exception} = <<END
---
Le distribuzioni immesse non hanno lo stesso numero di classi...

END
        ;
        croak $self->get_exception();
    }
    
    my $dist_diff = [ ];
    for (my $index = 0; $index < scalar @$dist_1; $index++) {
       $$dist_diff[$index] = sprintf ("%.4f", $$dist_1[$index] - $$dist_2[$index]);
    }
    
    return $dist_diff;
}

# calcola i valori critici per un test a due code
sub _critical_value_two_side {
    my ($self, %arg) = @_;
    
    # specifico le opzioni necessarie senza le quali PITA non funzionerebbe
    foreach my $opt ('pvalue', 'n1', 'n2') {
        unless (exists $arg{$opt}) {
            $self->{_exception} = <<END
---
Parametri mancanti, sintassi minima:
\$self->_critical_value_two_side(pvalue => alfa,
                                n1 => num_osservazioni_dist1,
                                n2 => num_osservazioni_dist2,)

END
            ;
            croak $self->get_exception();
        }
    }
    
    my %coeff = ( '0.001' => 1.95,
                  '0.005' => 1.73,
                  '0.01'  => 1.63,
                  '0.05'  => 1.36,
                  '0.1'   => 1.22,
                );
    
    unless (exists $coeff{$arg{'pvalue'}}) {
        $self->{_exception} = "\n---\nValore critico per alfa = $arg{'pvalue'} non tabulato\n";
        croak $self->get_exception();
    }
    
    my ($n1, $n2) = ( sprintf ("%.0f", $arg{'n1'}), sprintf ("%.0f", $arg{'n2'}) );
    my $J_value = $coeff{$arg{'pvalue'}} * sqrt(($n1 + $n2)/($n1 * $n2));

    return sprintf ("%.4f", $J_value);
    
}

# esegue il Kolmogorov-Smirnov Test
sub test {
    my ($self, %arg) = @_;
    
    $self->{_pvalue} = $arg{'alfa'} if (exists $arg{'alfa'});
    $arg{'mode'} = $self->get_mode() unless (exists $arg{'mode'}); 
    
    # specifico le opzioni necessarie senza le quali PITA non funzionerebbe
    foreach my $opt ('distref', 'distobs') {
        unless (exists $arg{$opt}) {
            $self->{_exception} = <<END

---
Parametri mancanti, sintassi:
\$self->test( distref => \\\@arg1, distobs => \\\@arg2,
             [alfa => \$arg3, mode => \$arg4]
            );
                       
ARGOMENTI:                       
distref --> distribuzione di riferimento
distobs --> distribuzione osservata
alfa    --> p-value (default 0.05)
mode    --> tipo del test ([oneside|twoside], default twoside)

END
            ;
            croak $self->get_exception();
        }
    }
    
    # memorizzo le distribuzioni tra gli attributi della classe
    $self->set_dist_obs_1($arg{'distref'});
    $self->set_dist_obs_2($arg{'distobs'});
    
    # memorizzo il numero di osservazioni per ogni distribuzione
    $self->{_n_obs_1} = $self->_count_obs($arg{'distref'});
    $self->{_n_obs_2} = $self->_count_obs($arg{'distobs'});
    
    # genero le distribuzioni delle frequenze relative
    $self->{_dist_rel_freq_1} = $self->_build_dist_rel_freq(dist => $self->get_dist_obs_1());
    $self->{_dist_rel_freq_2} = $self->_build_dist_rel_freq(dist => $self->get_dist_obs_2());
    
    # genero le distribuzioni cumulate
    $self->{_dist_cumul_1} = $self->_build_dist_cumul($self->get_dist_rel_freq_1());
    $self->{_dist_cumul_2} = $self->_build_dist_cumul($self->get_dist_rel_freq_2());
    
    # genero la distribuzione delle differenze tra le cumulate
    $self->{_dist_D} = $self->_build_dist_diff($self->get_dist_cumul_1(), $self->get_dist_cumul_2());
    
    # allestisco un case_of a seconda se il test è ad una o a due code
    $_ = $arg{'mode'};
    CASEOF: {
        /^oneside$/ && do {
            $self->{_exception} = "\n---\nIl test ad una coda non è ancora stato implementato\n";
            croak $self->get_exception();
        };
        /^twoside$/ && do {
            # per il test a due code considero la distribuzione delle differenze come valore assoluto
            my @abs_dist = map { abs $_ } @{$self->get_dist_D()};
            
            # prendo la differenza massima
            @abs_dist = sort {$b <=> $a} @abs_dist;
            $self->{_D_max} = shift @abs_dist;
            
            # calcolo il valore critico per i test a due code
            $self->{_J_value} = $self->_critical_value_two_side( pvalue => $self->get_pvalue(),
                                                                 n1 => $self->get_n_obs_1(),
                                                                 n2 => $self->get_n_obs_2());
            
           if ($self->{_D_max} > $self->{_J_value}) {
               return 1;
           } else {
               return 0;
           }
        };
        $self->{_exception} = "\n---\nModalità di test <$_> sconosciuta\n";
        croak $self->get_exception();
    }
    
}

1;

=head1 SPARTA::lib::KS_test

KS_test: test statistisco di Kolmogorov-Smirnov

Da impiegare per il confronto tra due distribuzioni osservate; in questa
classe viene applicato il metodo di Kolmogorv-Smirnov per 2 campioni
indipendenti con dati discreti o a gruppi.

=head1 Synopsis

    use SPARTA::lib::KS_test;
    my $obj = SPARTA::lib::KS_test->new();

    my $dist_A = [0,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    my $dist_B = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,1,1,0,0];

    my $result = $obj->test(distref => $dist_A, distobs => $dist_B, alfa => 0.05);

    print "\nD_max -> ", $obj->get_D_max();
    print "\nJ_val -> ", $obj->get_J_value();

    unless ($result) {
        print "\nLe distribuzioni sono significativamente differenti per P<", $obj->get_pvalue(), "\n";
    }


=head1 METHODS

=head2 test(distref => \\\@arg1, distobs => \\\@arg2, [alfa => \$arg3, mode => \$arg4])

    restituisce 1 se la distribuzione distobs è significativamente
    diversa dalla distribuzione distref.
    
    ARGOMENTI:                       
    distref --> distribuzione di riferimento
    
    distobs --> distribuzione osservata
    
    alfa    --> (OPZIONALE, default 0.05) P-value; i valori critici sono
    calcolati al momento solo per P pari a 0.001, 0.005, 0.01, 0.05, 0.1
    
    mode    --> (OPZIONALE, default twoside) specifica se condurre il
    KS-test a una o a due code; al momento è disponibile solo il test
    a due code
    
    NOTE:
    Il KS-test confronta due distribuzioni contenenti m ed n 
    osservazioni. I valori critici vengono calcolati con la formula
    
        J = sqrt(m*n/(m+n))*alfa
    
    Questa formula e' valida per un numero di osservazioni grande
    (n > 25). Il test non e' affidabile su campioni piccoli.

=head1 UPDATES


=cut
