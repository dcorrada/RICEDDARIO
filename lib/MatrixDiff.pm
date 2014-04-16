package RICEDDARIO::lib::MatrixDiff;

# to make STDOUT flush immediately, simply set the variable
# this can be useful if you are writing to STDOUT in a loop
# many times the buffering will cause unexpected output results
$| =1;

use lib $ENV{HOME};

###################################################################
use base ( 'RICEDDARIO::lib::Generic_class' ); # eredito la classe generica contenente il costruttore, l'AUTOLOAD ecc..
use base ( 'RICEDDARIO::lib::FileIO' ); # eredito la classe per gestire le lettura/scrittura di file
use Carp;
use Cwd;
our $AUTOLOAD;

# Definizione degli attributi della classe
# chiave        -> nome dell'attributo
# valore [0]    -> valore di default
# valore [1]    -> permessi di accesso all'attributo
#                  (lettura, modifica...)
# STRUTTURA DATI
our %_attribute_properties = (
     _mata      => [ { },  'read.'],        # input matrix
     _matb      => [ { },  'read.'],        # input matrix
     _switch    => [ '_mata', 'read.'],     # definisce l'attuale matrice di input su cui sovrascrivere i dati
     _diffmat   => [ { },  'read.']        # output matrix
);

# Unisco gli attributi della classi madri con questa
my $ref = RICEDDARIO::lib::Generic_class::_hash_joiner(\%RICEDDARIO::lib::Generic_class::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = RICEDDARIO::lib::Generic_class::_hash_joiner(\%RICEDDARIO::lib::FileIO::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;


sub import_gpl {
    my ($self, $filename) = @_;
    
    print "\n-- importo il file [$filename]...";
    if ($filename) {
        $self->{'_filename'} = $filename;
    } else {
        $self->{'_exception'} = "\n-E impssibile inizializzare l'attributo [_filename]\n\t";
        $self->_raise_error();
    }
    
    $self->{'_switch'} = $self->{'_switch'} eq '_mata' ? '_matb' : '_mata';
    my $matx = $self->get_switch();
#     printf("\n-- sovrascrivo l'attributo [%s]", $matx);
    
    $self->read();
    my @content = @{$self->get_filedata()};
    
    
    $self->{$matx} = { }; # re-inizializzo l'attributo
    
    while (my $row = shift @content) {
        chomp $row;
        next if ($row =~ m/^\s*$/);
        my ($x, $y, $z) = $row =~ m/([\d\.\-e]+)\s+([\d\.\-e]+)\s+([\d\.\-e]+)/i;
        ${$self->{$matx}}{$x} = { } unless (exists ${$self->{$matx}}{$x});
        if (exists ${$self->{$matx}->{$x}}{$y}) {
            $self->{'_exception'} = sprintf("\nE- ridondanza di dati in [%s] ([%s]:[%s])\n\t", $matx, $x, $y);
            $self->_raise_error();
        } else {
            ${$self->{$matx}->{$x}}{$y} = $z;
        }
    }
    print ("OK");
}

sub _exec_diff { # metodo privato, questa sub calcola effettivamente la differenza tra le due matrici
    my ($self) = @_;
    
    # in primo luogo verifico di avere le matrici su cui operare
    unless (%{$self->{'_mata'}} && %{$self->{'_matb'}}) {
        $self->{'_exception'} = "\nE- matrici in input non inizializzate\n\t";
        $self->_raise_error();
    }
    
    my @elem = sort {$a <=> $b} keys %{$self->{'_mata'}};
    
    foreach my $x (@elem) {
        foreach my $y (@elem) {
            if ($self->{'_mata'}->{$x}->{$y} and $self->{'_matb'}->{$x}->{$y}) {
                $self->{'_diffmat'}->{$x} = { } unless (exists ${$self->{'_diffmat'}}{$x});
                my $diff = $self->{'_mata'}->{$x}->{$y} - $self->{'_matb'}->{$x}->{$y};
                $self->{'_diffmat'}->{$x}->{$y} = sprintf ("%.6f", $diff);
            }
        }
    }
}

sub export_gpl {
    my ($self, $filename) = @_;
    
    if ($filename) {
        $self->{'_filename'} = $filename;
    } else {
        $self->{'_filename'} = 'matrix.diff.dat';
    }
    
    printf("\n-- scrivo il file [%s]...", $self->get_filename());
    $self->_exec_diff(); # calcolo la matrice di differenza;
    
    my $matrix = $self->{'_diffmat'};
    
    my @cols = sort {$a <=> $b} keys %{$matrix};
    my @rows = sort {$a <=> $b} keys %{$matrix->{$cols[1]}};
    
    $self->{'_filedata'} = [ ]; # re-inizializzo l'attributo
    foreach my $x (@cols) {
        foreach my $y (@rows) {
            my $z = $matrix->{$x}->{$y};
            my $string = pack('A7A7', $x, $y);
            $string .= "$z\n";
            push(@{$self->{'_filedata'}}, $string);
        }
        push(@{$self->{'_filedata'}}, "\n");
    }
    
    $self->write();
    print "OK";
}


1;

=head1 RICEDDARIO::lib::MatrixDiff

    Classe per generare matrici di differenza per GnuPlot o in formato XPM

=head1 Synopsis

    use RICEDDARIO::lib::MatrixDiff;
    
    my $obj = RICEDDARIO::lib::MatrixDiff->new();

    # importo le due matrici da confrontare
    $obj->import_gpl("matrix.APO.dat");
    $obj->import_gpl("matrix.OLO.dat");
    
    # calcolo e salvo su file la matrice differenza
    $obj->export_gpl();
    
    
=head1 METHODS

=head2 import_gpl($nomefile)

    legge un file contenente la matrice e lo assegna all'attributo _mata o 
    _matb; il file deve essere in formato x GnuPlot. Nel file di esempio 
    seguente ho una matrice simmetrica 3x3: 
     
     MATRIX.dat:
        1 1 0.00
        1 2 0.10
        1 3 0.09
        
        2 1 0.10
        2 2 0.00
        2 3 0.52
          
        3 1 0.09
        3 2 0.52
        3 3 0.00

=head2 _exec_diff()

    compara le due matrici date dagli attributi '_mata' e '_matb' e scrive
    sull'attributo '_diffmat' la matrice differenza

=head2 export_gpl([$nomefile])

    calcola, usando il metodo '_exec_diff', ed esporta la matrice differenza su
    un file in formato per GnuPlot, definito da $nomefile
    (default: 'matrix.diff.dat')

=head1 UPDATES

=head2 2011-oct-19

    * prima release


=cut
