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
use Spreadsheet::WriteExcel;
use BRENDA::lib::FileIO;
use Cwd;
use Carp;

## GLOBS ##
our $file_obj = BRENDA::lib::FileIO->new();
our $rawdata = { };
our $statistics = { };
## SBLOG ##

print "\n*** BRENDA.statistics ***\n";

READCSV: { # leggo il file in input 
    my $filename = $ARGV[0];
    print "I- reading [$filename]...\n";
    $file_obj->set_filename($filename);
    my $content = $file_obj->read();
    
    # leggo l'intestazione x definire i campi di $raw_data
    my $header = shift @{$content};
    chomp $header;
    my @fields = split(';', $header);
    shift @fields;
    
    # ora leggo i singoli valori
    while (my $row = shift @{$content}) {
        chomp $row;
        next unless $row;
        my @values = split(';', $row);
        my $system = shift @values;
        $rawdata->{$system} = { } unless (exists $rawdata->{$system});
        for (my $i = 0; $i < scalar @values; $i++) {
            $rawdata->{$system}->{$fields[$i]} = [ ] unless (exists $rawdata->{$system}->{$fields[$i]});
            push(@{$rawdata->{$system}->{$fields[$i]}}, $values[$i]);
        }
    }
}

STATISTICS: { # calcolo le statistiche dei dati grezzi
    print "I- calculating statistics\n";
    foreach my $system (keys %{$rawdata}) {
        printf("\tprocessing [%s]...\n", $system);
        foreach my $field (keys %{$rawdata->{$system}}) {
            my $filtered = outliers($rawdata->{$system}->{$field},'fill');
            @{$rawdata->{$system}->{$field}} = @{$filtered->{'data'}};
            $statistics->{$system} = { } unless (exists $statistics->{$system});
            $statistics->{$system}->{$field . '_mean'} = $filtered->{'mean'};
            $statistics->{$system}->{$field . '_stddev'} = $filtered->{'stddev'};
        }
    }
}

DELTA: {
    print "I- calculating deltas\n";
    foreach my $system (keys %{$rawdata}) {
        printf("\tprocessing [%s]...\n", $system);
        foreach my $field ('ELE_', 'VDW_', 'ASA_') {
            my $deltas = [ ];
            my $diff;
            my ($rec, $lig, $com) = (
                $rawdata->{$system}->{$field . 'r'},
                $rawdata->{$system}->{$field . 'l'},
                $rawdata->{$system}->{$field . 'c'}
            );
            for (my $r = 0; $r < scalar @{$rec}; $r++) {
                for (my $l = 0; $l < scalar @{$lig}; $l++) {
                    for (my $c = 0; $c < scalar @{$com}; $c++) {
                        $diff = $com->[$c] - ($lig->[$l] + $rec->[$r]);
                        $diff = sprintf("%.3f", $diff);
                        push(@{$deltas}, $diff);
                    }
                }
            }
            
            my $filtered = outliers($deltas,"nofill");
            $statistics->{$system}->{'d' . $field . 'mean'} = $filtered->{'mean'};
            $statistics->{$system}->{'d' . $field . 'stddev'} = $filtered->{'stddev'};
        }
    }
}

EXCEL: {
    print "I- writing Excel output file...\n";
    
    my $workbook = Spreadsheet::WriteExcel->new('BRENDA.statistics.xls');

    # rawdata worksheet
    my $worksheet = $workbook->add_worksheet('rawdata');
    my $header = [ 'SYSTEM', 'ELE_r', 'VDW_r', 'ASA_r', 'ELE_l', 'VDW_l', 'ASA_l', 'ELE_c', 'VDW_c', 'ASA_c' ];
    $worksheet->write_row(0, 0, $header);
    my $i = 1;
    foreach my $system (keys %{$statistics}) {
        for (my $j = 0; $j < scalar @{$rawdata->{$system}->{'ELE_r'}}; $j++) {
            my $row = [
                $system,
                $rawdata->{$system}->{'ELE_r'}->[$j],
                $rawdata->{$system}->{'ELE_l'}->[$j],
                $rawdata->{$system}->{'ELE_c'}->[$j],
                $rawdata->{$system}->{'VDW_r'}->[$j],
                $rawdata->{$system}->{'VDW_l'}->[$j],
                $rawdata->{$system}->{'VDW_c'}->[$j],
                $rawdata->{$system}->{'ASA_r'}->[$j],
                $rawdata->{$system}->{'ASA_l'}->[$j],
                $rawdata->{$system}->{'ASA_c'}->[$j]
            ];
            $worksheet->write_row($i, 0, $row);
            $i++;
        }
    }
    
    # statistics worksheet
    $worksheet = $workbook->add_worksheet('statistics');
    $header = [ 'SYSTEM', '[Xaxis]',  'dELE_mean', 'dELE_stddev',  'dVDW_mean', 'dVDW_stddev',  'dASA_mean', 'dASA_stddev' ]; # [Xaxis] sarebbe una colonna di valori da inserire manualmente nel file Excel successivamente, qui serve solo per definire un asse X su cui generare gli scatter plot
    $worksheet->write_row(0, 0, $header);
    $i = 1;
    foreach my $system (keys %{$statistics}) {
        my $row = [
            $system,
            $i,
            $statistics->{$system}->{'dELE_mean'},
            $statistics->{$system}->{'dELE_stddev'},
            $statistics->{$system}->{'dVDW_mean'},
            $statistics->{$system}->{'dVDW_stddev'},
            $statistics->{$system}->{'dASA_mean'},
            $statistics->{$system}->{'dASA_stddev'},
        ];
        $worksheet->write_row($i, 0, $row);
        $i++;
    }
    
    # scatter plot
    my $cats = (scalar keys %{$statistics}) + 1;
    
    my $chart = $workbook->add_chart( name => 'scatter_ELE', type => 'scatter' );
    $chart->add_series(
        'categories' => '=statistics!$B$2:$B$' . $cats,
        'values'     => '=statistics!$C$2:$C$' . $cats,
    );
    $chart->set_title( name => 'electrostatics' );
    $chart->set_x_axis( name => '[Xaxis]' );
    $chart->set_y_axis( name => 'energy (kJ/mol)' );
    
    $chart = $workbook->add_chart( name => 'scatter_VDW', type => 'scatter' );
    $chart->add_series(
        'categories' => '=statistics!$B$2:$B$' . $cats,
        'values'     => '=statistics!$E$2:$E$' . $cats,
    );
    $chart->set_title( name => 'van der Waals' );
    $chart->set_x_axis( name => '[Xaxis]' );
    $chart->set_y_axis( name => 'energy (kJ/mol)' );
    
    $chart = $workbook->add_chart( name => 'scatter_SASA', type => 'scatter' );
    $chart->add_series(
        'categories' => '=statistics!$B$2:$B$' . $cats,
        'values'     => '=statistics!$G$2:$G$' . $cats,
    );
    $chart->set_title( name => '(solvent) accessible surface area' );
    $chart->set_x_axis( name => '[Xaxis]' );
    $chart->set_y_axis( name => 'ASA (A)' );
    
    $workbook->close();
    
}

FINE: {
    print "\n*** scitsitats.ADNERB ***\n";
    exit;
}

sub outliers { # individuo gli outliers
    
    my ($data,$mode) = @_;
    
    my $string = join(', ', @{$data});
    my $scRipt;
    if ($mode eq "fill") { # sostituisco gli outlier con valori medi, da usare per dataset piccoli
        $scRipt = <<END
library(outliers);
x = c( $string );
repeat {
    res = grubbs.test(x, type = 20);
    if (res\$p.value >= 0.05) break;
    x = rm.outlier(x,fill = TRUE);
}
cat(x, fill = TRUE);
cat(mean(x), sd(x), fill = TRUE);
END
        ;
    } elsif ($mode eq "nofill") { # rimuovo gli outlier fino a tenere il 75% dei dati (var "l"), da usare per dataset grossi
        $scRipt = <<END
library(outliers);
x = c( $string );
if (length(x) > 20) x = sample(x, 20)
l = length(x) * 0.75;
repeat {
    res = grubbs.test(x, type = 20);
    if (length(x) < l) break;
    if (res\$p.value >= 0.05) break;
    x = rm.outlier(x,fill = FALSE);
}
cat(x, fill = TRUE);
cat(mean(x), sd(x), fill = TRUE);
END
        ;
    } else {
        croak("\nE- no filtering mode defined...\n\t");
    }
    
    my $Rbin = whichR();
    $file_obj->set_filename('script.R');
    $file_obj->set_filedata([ $scRipt ]);
    $file_obj->write();
    my $Rlog = qx/$Rbin script.R 2>&1/;
#     print $Rlog;
    unlink 'script.R';
    
    my @content = split(">", $Rlog);
    my $outliers = { 'data' => [ ], 'mean' => '', 'stddev' => '' };
    while (my $newline = shift @content) {
        chomp $newline;
        # raccolgo i dati filtrati
        if ($newline =~ /cat\(x, fill = TRUE\);/) {
            @{$outliers->{'data'}} = grep(/[\d\.\-]+/, split(/\s+/, $newline));
        }
        # raccolgo media e deviazione standard
        if ($newline =~ /cat\(mean\(x\), sd\(x\), fill = TRUE\);/) {
            ($outliers->{'mean'}, $outliers->{'stddev'}) = grep(/[\d\.\-]+/, split(/\s+/, $newline));
        }
    } 
#     
    return $outliers;
}

sub whichR { # verifico che R sia installato
    my $Rbin = qx/which R 2> \/dev\/null/;
    chomp $Rbin;
    croak("\nE- R software not found\n\t") unless $Rbin;
    $Rbin .= ' --vanilla <'; # opzione per farlo girare in batch
    return $Rbin;
}