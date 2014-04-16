#
# Gestisce la lettura e la scrittura di files
#

package my_PERL::misc::FileIO;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| =1;

use strict;
use warnings;
use Carp;
our $AUTOLOAD;

# Variabili e metodi interni alla classe
{ 
# Definizione degli attributi della classe
# chiave        -> nome dell'attributo
# valore [0]    -> valore di default
# valore [1]    -> permessi di accesso all'attributo
#                  (lettura, modifica...)
    my %_attribute_properties = (
        _filename    => [ '',   'read.write'],
        _filedata    => [ [ ],  'read.write']
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
                print "\nAttributo _$arg non previsto";
                $attributes_not_found++;
            }
        }
        return $attributes_not_found;
    }

# apre il file, ritorna il FileHandle del file aperto
sub _openfile {
    my($self, $filename, $writemode) = @_;
    my $fh;
    # aggiunge una modalita' di accesso al file se specificata (>, >>, +> ...)
    $writemode and my $mode = $writemode . $filename;
    
    open($fh, $mode) or croak ("\nImpossibile aprire il file $filename");
    return $fh;
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
            $self->{$attribute} = $arg{$1};
        # ...o con il valore di default altrimenti
        } else {
            $self->{$attribute} = $self->_attribute_default($attribute);
        }
    }
    $self->_check_attributes(keys %arg);
    
    # se viene passato l'attributo _filename l'oggetto tenta di leggere
    # automaticamente il file
    $self->read($self->get_filename()) if (exists $arg{filename});
    
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
            # controlla che l'attrubuto abbia il permesso in scrittura
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

# Legge il file e ritorna un array con il contenuto
sub read {
   my ($self, $filename) = @_; 
   
   my $fh = $self->_openfile($filename, '<');
   $self->set_filename($filename);
   $self->set_filedata([ <$fh> ]);
   close $fh;
   return $self->get_filedata();
}

# Scrive su file
# Il contenuto da inserire nel file ($filedata) DEVE essere 
# passato come REF di un ARRAY
#
# Se non vengono specificati argomenti scrive un file utilizzando gli
# attributi impostati per l'oggetto (_filename e _filedata)
sub write {
    my ($self, %arg) = @_;
    my $inputs = {
        filename	=> $arg{'filename'}		|| $self->get_filename(),
		filedata	=> $arg{'filedata'}	    || $self->get_filedata(),
    };
    
    # Definisce la modalità di scrittura sul file
    # di default è '>' (prima scrittura su un file nuovo, cancella 
    # l'eventuale file esistente, anche se il metodo $self->_openfile
    # te lo chiede prima)
    my $write_mode = '>';
    $write_mode = $arg{'mode'} if $arg{'mode'};
    
    my $fh = $self->_openfile($inputs->{'filename'}, $write_mode);
    $self->set_filename($inputs->{'filename'});
    @{$inputs->{'filedata'}} and my @filedata = @{$inputs->{'filedata'}};
    $self->set_filedata($inputs->{'filedata'});
    print $fh @filedata;
    close $fh;
}

1;

=head1 my_PERL::FileIO

FileIO: read and write file data

=head1 Synopsis

    use my_PERL::misc::FileIO;

    my $file_obj = my_PERL::misc::FileIO->new();

    my $new_file_content = [
        "Oggi e\' proprio una bella giornata,\n",
        "quindi mi sento in vena di dire:\n\n",
        "\t\"CIAO MONDO!!!\"\n",
        ];

    # Aggiorno l'attributo _filedata con il contenuto di $new_file_content
    $file_obj->set_filedata($new_file_content);

    # Creo un nuovo file in cui riverso il contenuto dell'attributo _filedata
    $file_obj->write(filename => 'test_file.txt');

    # Leggo il file appena creato
    print @{$file_obj->read('test_file.txt')};


=head1 METHODS

=head2 read($nomefile)

    legge un file e ritorna un array-ref con il contenuto del file;
    $nomefile e' un argomento opzionale, modifica l'attributo _nomefile
    dell'oggetto.

=head2 write(filedata => \@contenutofile, filename => $nomefile)

    scrive su un file; le chiavi di hash {filedata} e {filename} sono
    argomenti opzionali, modificano gli attributi _nomefile e _filedata
    dell'oggetto

=head1 UPDATES

=head2 2009-feb-4

    * aggiornamento del metodo <write>: aggiunta del parametro
      $arg{'mode'} x definire le modalità di scrittura

=cut
