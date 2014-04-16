package RICEDDARIO::lib::Kabat;

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
use strict;
use base ( 'RICEDDARIO::lib::Generic_class' ); # eredito la classe generica contenente il costruttore, l'AUTOLOAD ecc..
use base ( 'RICEDDARIO::lib::FileIO' ); # eredito la classe per gestire le lettura/scrittura di file
use Carp;
use LWP::UserAgent;
use File::Spec::Unix;
use Spreadsheet::Write; # x scrivere l'output in file Excel
our $AUTOLOAD;

# Definizione degli attributi della classe
# chiave        -> nome dell'attributo
# valore [0]    -> valore di default
# valore [1]    -> permessi di accesso all'attributo
#                  ('read.[write.[...]]')
# STRUTTURA DATI
our %_attribute_properties = (
    _abnum_url     => ['http://www.bioinf.org.uk/cgi-bin/abnum/abnumpdb.pl', 'read.'],
);

# Unisco gli attributi della classi madri con questa
my $ref = RICEDDARIO::lib::Generic_class::_hash_joiner(\%RICEDDARIO::lib::Generic_class::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;
$ref = RICEDDARIO::lib::Generic_class::_hash_joiner(\%RICEDDARIO::lib::FileIO::_attribute_properties, \%_attribute_properties);
%_attribute_properties = %$ref;


sub _abnum { # _abnum([file => $filename, [scheme => $scheme]])

# Dato in input un file PDB restituisce un array contenente il PDB stesso
# rinumerato secondo le nomenclature immplementate da abnum.
# * file    (default: attributo _filename) nome del file PDB
# * scheme  (default: '-k') schema di numerazione.
#    '-k' numerazione Kabat; '-c' numerazione Chothia;
#    '-a' numerazione Chothia corretta secondo;

    my ($self, %opt) = @_;
    
    my ($pdb_file, $pdb_code, $scheme); 
    INPUT_CHECK: {
        $pdb_file = $opt{'file'} ? $opt{'file'} : $self->get_filename();
        $self->_raise_error(sprintf("\nE- [%s] file not found\n\t", $pdb_file))
            unless (-e $pdb_file);
        
        $scheme = $opt{'scheme'} ? $opt{'scheme'} : '-k';
        $self->_raise_error(sprintf("\nE- [%s] numbering scheme unknown\n\t", $scheme))
            unless (grep(/^$scheme$/, '-k', '-c', '-a'));
        
        my %numbering = ('-k' => 'Kabat', '-c' => 'Chothia', '-a' => 'extended Chothia');
#         print "\nFILE.....: $pdb_file\nSCHEME...: $numbering{$scheme}\n";
    }
    
    SUBMISSION: {
        print "\nI- sending request...";
        my $bot = LWP::UserAgent->new();
        $bot->agent('libwww-perl/5.805');
        
        my $request = $bot->post(
            $self->get_abnum_url(),
            Content_type => 'multipart/form-data',
            Content => [
                scheme  => $scheme,
                pdb     => [ $pdb_file ]
            ]
        );
        
        $request->is_error() and do {
            $self->_raise_error(sprintf("\nE- %s [%s]\n\t", $request->status_line, $request->base));
        };
        
        $request->is_success() and do {
            my $content = $request->content();
            if ($content !~ m/\nATOM/) { # abnum non ha prodotto il file giusto
                my $log_name = $self->get_workdir() . '/abnum_ERR.log';
                my $log_data = [ $content ];
                $self->write(filename => $log_name, filedata => $log_data);
                $self->_raise_error(sprintf("\nE- abnum output error, see [%s]\n\t", $log_name));
            }
            my $count = ($content =~ tr/\n/\n/);
            my $bytes = length $content;
            @{$self->{'_filedata'}} = split("\n", $content);
            print "done";
#             printf("done [%s - %d lines, %d bytes]", $request->base, $count, $bytes);
        };
    }
    
    return $self->get_filedata();
}


sub numbers {
    my ($self, $pdb) = @_;
    
    INPUT_CHECK: {
        $pdb or $pdb = $self->get_filename();
        $self->_raise_error(sprintf("\nE- [%s] file not found\n\t", $pdb))
            unless (-e $pdb);
    };
    
    my ($volume,$source_dir,$noext) = File::Spec::Unix->splitpath($pdb);
    ($noext) = $noext =~ m/^(\w+)\.\w+$/;
    my $xls = $self->get_workdir() . '/' . $noext . '.xls'; # output file
#     print "\nI- input  [$pdb]\nI- output [$csv]";
    

    
    my $template = { }; # templato su cui costruirò il file di output
    PARSE_PDB: { # parsing del pdb in input
        # estraggo solo le righe contenenti i C alpha
        my @pdb_content = @{$self->read($pdb)};
        @pdb_content = grep(/^ATOM\s+\d+\s+CA\s+/, @pdb_content);
        
        # x ogni riga scrivo su template: residue, resnumber, chain
        # la primary key di template coincide con l'atom number
        while (my $record = shift @pdb_content) {
            my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $record);
            $template->{sprintf("%05d", $splitted[1])}->{'pdb'} = "$splitted[5] $splitted[7] $splitted[8]";
        }
    };
    
    PARSE_ABNUM: { # parsing dei pdb ottenuti da abnum
        my %numbering = ('-k' => 'Kabat', '-c' => 'Chothia', '-a' => 'Chothia_fixed');
        foreach my $scheme ('-k', '-c', '-a') { # richiedo un pdb per ogni tipo di nomenclatura
            printf("\nI- [%s] -> %s", $noext, $numbering{$scheme});
            my @abnum_content = @{$self->_abnum(file => $pdb, scheme => $scheme)};
            # estraggo solo le righe contenenti i C alpha
            @abnum_content = grep(/^ATOM\s+\d+\s+CA\s+/, @abnum_content);
            while (my $record = shift @abnum_content) { # aggiorno $template con il resnumber modificato
                my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $record);
                $template->{sprintf("%05d", $splitted[1])}->{$numbering{$scheme}} = $splitted[8] . $splitted[9];
            }
        }
    };
    
    WRITE_EXCEL: { # scrivo un output file in formato xls
        my $sheet = Spreadsheet::Write->new(
            'file'      =>  $xls,
            'format'    =>  'xls',
            'sheet'     =>  'abnum'
        );
        
        $sheet->addrow(
            { 'content' => 'resname', 'font_weight' => 'bold'},
            { 'content' => 'chain', 'font_weight' => 'bold'},
            { 'content' => 'resid', 'font_weight' => 'bold'},
            { 'content' => 'Kabat', 'font_weight' => 'bold'},
            { 'content' => 'Chothia', 'font_weight' => 'bold'},
            { 'content' => 'Chothia_fixed', 'font_weight' => 'bold'}
        );
        
        foreach my $key (sort keys %{$template}) {
            if (exists $template->{$key}->{'Kabat'}) {
                my ($resname, $chain, $resid) = $template->{$key}->{'pdb'} =~ m/^(\w{3,4})\s+(\w{1})\s+(\d+)$/g;
                my ($k) = $template->{$key}->{'Kabat'} =~ /(\w+)/;
                my ($c) = $template->{$key}->{'Chothia'} =~ /(\w+)/;
                my ($a) = $template->{$key}->{'Chothia_fixed'} =~ /(\w+)/;
                $sheet->addrow($resname, $chain, {'content' => $resid, 'align' => 'left'}, {'content' => $k, 'align' => 'left'}, {'content' => $c, 'align' => 'left'}, {'content' => $a, 'align' => 'left'});
            }
        };
    }
    
    # allestisco cosa deve tornare dal metodo
    $self->set_filedata([ "PDB;Kabat;Chothia;Chothia_fixed;\n" ]);
    foreach my $key (sort keys %{$template}) {
        if (exists $template->{$key}->{'Kabat'}) {
            
            my $string = join(';', $template->{$key}->{'pdb'}, $template->{$key}->{'Kabat'}, $template->{$key}->{'Chothia'}, $template->{$key}->{'Chothia_fixed'}, "\n");
            push(@{$self->{_filedata}}, $string);
        }
    }
    
    print "\n";
    return $self->get_filedata();
}

1;

=head1 RICEDDARIO::lib::Kabat

    Classe per gestire i Fab

=head1 Synopsis

    use RICEDDARIO::lib::Kabat;
    my $obj = RICEDDARIO::lib::Kabat->new();

    my $file = "1AFV.pdb";
    my $content = $obj->numbers($file);
    
    # content è un array ref
    foreach (@{$content}) { print $_ };
    
    
=head1 METHODS

=head2 numbers([file => $filename])

    file    (default: attributo _filename) nome del file PDB
    
    Dato in input un file PDB restituisce un array ref contenente le diverse
    numerazioni di riferimento attualmente usate [1]. Il file in input
    viene sottomesso al servizio web abnumpdb, disponibile su
    http://www.bioinf.org.uk/abs/abnum/. In output viene restituito un tabulato
    analogo al seguente:
    
        PDB;Kabat;Chothia;Chothia_fixed;
        GLN H    1;   1 ;   1 ;   1 ;
        VAL H    2;   2 ;   2 ;   2 ;
        GLN H    3;   3 ;   3 ;   3 ;
        LEU H    4;   4 ;   4 ;   4 ;
        [...]
    
    Il tabulato viene esportato in un file Excel.
    
    [1] Abhinandan KR, Martin AC. - Mol Immunol. 2008 Aug;45(14):3832-9

=head1 UPDATES

=head2 2011-nov-30

    * prima release

=cut
