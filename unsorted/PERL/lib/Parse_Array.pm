package my_PERL::misc::Parse_Array;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| =1;

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
    my %_attribute_properties = (
        
        # array da confrontare
        _array_A         => [ [ ],   'read.write'],
        _array_B         => [ [ ],   'read.write'],
        
        # elementi che sono presenti esclusivamente in _array_A
        # e _array_B, rispettivamente
        _array_diff_A    => [ [ ],   'read'],
        _array_diff_B    => [ [ ],   'read'],
        
        # elementi condivisi da _array_A e _array_B
        _array_shared    => [ [ ],   'read'],
        
        # hash contenenti le ripetizioni in _array_A; le chiavi
        # identificano gli elementi dell'array, i valori il numero di
        # ripetizioni per ogni elemento
        _repeated        => [ { },    'read'],
         
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
    \w+::	return $_attribute_properties{$attribute}[0];
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

# Re-inizializza gli attributi dell'oggetto
# (in questo caso tutti gli attributi in sola lettura vengono
# inizializzati come indefiniti; MODIFICARE QUESTA SUB per metodi di
# inizializzazione differenti)
    sub _reinit {
        my ($self) = @_;
        
        foreach my $attribute (_all_attributes) {
            unless ($self->_permissions($attribute, 'write')) {
                undef ($self->{$attribute});
            }
        }
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

# Metodo compare per confrontare elementi comuni in coppie di array
sub compare {
    my ($self) = @_;
    my  $i; #contatore generico
    my $output = { };
    
    $self->_reinit();
    
    # Popolamento dell'attributo _array_shared con gli elementi comuni
    # agli attributi _array_A e _array_B
    for my $array_A_elem (0..(scalar(@{$self->{_array_A}}))-1) {
        for my $array_B_elem (0..(scalar(@{$self->{_array_B}}))-1) {
            if ($self->{_array_A}->[$array_A_elem] eq $self->{_array_B}->[$array_B_elem]) {
                push (@{$self->{_array_shared}}, $self->{_array_A}->[$array_A_elem]);
            }
        }
    }
    
    @{$self->{_array_diff_A}} = @{$self->{_array_A}};
    @{$self->{_array_diff_B}} = @{$self->{_array_B}};
    
    # Eliminazione da _array_diff_A e _array_diff_B degli elementi gia'
    # presenti in _array_shared    
    foreach my $shared_elem (@{$self->{_array_shared}}) {
        $i = 0;
        foreach (@{$self->{_array_diff_A}}) {
            if ($shared_elem eq $_) {
                splice(@{$self->{_array_diff_A}}, $i, 1);
                last;
            }
            $i++;
        }
        $i = 0;
        foreach (@{$self->{_array_diff_B}}) {
            if ($shared_elem eq $_) {
                splice(@{$self->{_array_diff_B}}, $i, 1);
                last;
            }
            $i++;
        }
    }
        
    $output->{only_A} = $self->get_array_diff_A();
    $output->{only_B} = $self->get_array_diff_B();
    $output->{shared} = $self->get_array_shared();
    
    return $output;
    
}


# Metodo repeats per individuare elementi ripetuti in un array
sub repeats {
    my ($self) =  @_;
    my $array = $self->get_array_A();
    $self->_reinit();
    
    foreach my $elem (@{$array}) {
        if (exists($self->{'_repeated'}->{$elem})) {
            $self->{'_repeated'}->{$elem}++
        } else {
            $self->{'_repeated'}->{$elem} = 1;
        }
    }
    
    return $self->get_repeated();
}

1;

=head1 my_PERL::Parse_Array

Analizza il contenuto di array

=head1 Synopsis

    use my_PERL::Parse_Array;

    # definisco gli array da confrontare
    my $array_1 = ['pippo', 'pluto', 'topolino', 'DISNEY'];
    my $array_2 = ['paperino', 'DISNEY', 'quiquoqua'];

    my $object = my_PERL::Parse_Array->new();

    # inizializzo l'oggetto con i due array
    $object->set_array_A($array_1);
    $object->set_array_B($array_2);

    # confronto gli array usando il metodo compare
    my %differences = %{$object->compare()};

    print 'Elementi esclusivi di @array_1...: ', "@{$differences{'only_A'}}\n";
    print 'Elementi esclusivi di @array_2...: ', "@{$differences{'only_B'}}\n";
    print 'Elementi condivisi...............: ', "@{$differences{'shared'}}\n\n";
    
    # Definisco un array contenente elementi ripetuti (il valore 'pippo' ad es.)
    my $repeated_array = ['pippo', 'pluto', 'paperino', 'pippo', 'quiquoqua'];
    
    # inizializzo l'oggetto con l'array
    $object->set_array_A($repeated_array);
    
    # Ricerco gli elementi ripetuti
    my $repeated_elems = $object->repeats();
    
    foreach (keys(%{$repeated_elems})) {
        printf ("L'elemento %s in \$repeated_elems viene ripetuto %i volte\n", $_, $repeated_elems->{$_});
    } 
    
    
=head1 METHODS

=head2
    compare( )

    confronta coppie di array; ritorna un hash-ref
    
    only_A => [...]
    only_B => [...]
    shared => [...]
    
    {only_A} e {only_B} contengono gli elementi che sono presenti
    esclusivamente in uno solo dei due array confrontati;
    
    {shared} contiene gli elementi condivisi da entrambi gli array.

=head2
    repeats( )

    cerca elementi ripetuti in un array; ritorna un hash-ref
    
    elem1 => num1
    elem2 => num2
    .
    .
    elemx => numx
    
    Le chiavi (elem) contengono gli elementi unici dell'array, i valori
    (num) quante volte l'elemento viene ripetuto nell'array

=head1 UPDATES

=cut
