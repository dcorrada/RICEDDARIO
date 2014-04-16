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
# Lanciare EMMA in un passo solo ho notato che divora memoria. Di conseguenza ho
# creato questo script che viene richiamato di volta in volta da EMMA per
# lanciare i diversi passaggi.
use Cwd;
use Carp;
use EMMA::lib::FileIO;
use Statistics::Descriptive;
use Memory::Usage;

## GLOBS ##
our $file_obj = EMMA::lib::FileIO->new(); # oggetto per leggere/scrivere su file
our $content = [ ]; # buffer in cui butto dentro il contenuto dei file 
our $mu = Memory::Usage->new();
our $par_file = $ARGV[0] || 'null';
our $mode = $ARGV[1] || 'null';
our $par = { };
## SBLOG ##

INIT: {
    $mu->record('start'); # monitoraggio memoria
    
    # leggo il file dei parametri
    goto FINE if ($par_file eq 'null');
    $file_obj->set_filename($par_file);
    $content = $file_obj->read();
    while (my $newline = shift @{$content}) {
        chomp $newline;
        my ($key,$value) = $newline =~ /^(\w+) = (.+)$/;
        $par->{$key} = $value
    }
    my $string = $par->{'ranges'};
    $par->{'ranges'} = [ ];
    unless ($string eq 'null') {
        foreach my $range (split ',', $string) {
            unless ($range =~ /^[-\d]+-[-\d]+$/) {
                carp("\nW- No valid range [$range], skipped\n\t");
                next;
            }
            my @boundaries = $range =~ /^([-\d]+)-([-\d]+)$/;
            @boundaries = sort { $a <=> $b } @boundaries;
            my $array = [ $boundaries[0]..$boundaries[1] ];
            push(@{$par->{'ranges'}}, $array);
        }
    }
    
}

CORE: {
    printf("\n*** START [%s] %s ***\n", $mode, clock());
    
    # components.pl verrà lanciato secondo una delle sguenti modalità (scelta in input)
    $mode =~ /^subset$/ and do { subset(); };
    $mode =~ /^samplecluster$/ and do { samplecluster(); };
    $mode =~ /^sampling$/ and do { sampling(); };
    $mode =~ /^ave$/ and do { ave(); };
    $mode =~ /^flumat$/ and do { flumat(); };
    $mode =~ /^diago$/ and do { diago(); };
    $mode =~ /^forecast$/ and do { forecast(); };
    $mode =~ /^minimal$/ and do { minimal(); };
    $mode =~ /^distrib$/ and do { distrib(); };
    $mode =~ /^total$/ and do { total(); };
    $mode =~ /^driven$/ and do { driven(); };
    $mode =~ /^propensity$/ and do { propensity(); };
    $mode =~ /^cytoscape$/ and do { cytoscape(); };
}

FINE: {
    $mu->record('stop'); # monitoraggio memoria
    # Report finale:
    my ($memdata) = $mu->state();
    my ($rss,$shared,$data) = (
        sprintf("%.3f", ($memdata->[1][3] - $memdata->[0][3])/1000),
        sprintf("%.3f", ($memdata->[1][4] - $memdata->[0][4])/1000),
        sprintf("%.3f", ($memdata->[1][5] - $memdata->[0][5])/1000)
    );
    my $performance = "resident: $rss MB\tshared: $shared MB\tstack: $data MB";
    printf("*** STOP [%s] %s ***\n%s\n", $mode, clock(), $performance);
    exit;
}

sub cytoscape {
    # esporto una struttura di riferimento e la parso
    my $cmd  = sprintf(
        "%s -f %s -o %s/topol.pdb ",
        $par->{'editconf'},
        $par->{'tpr_file'},
        $par->{'workdir'}
    );
    qx/$cmd 2>&1/;
    $file_obj->set_filename($par->{'workdir'} . '/topol.pdb');
    $content = $file_obj->read();
    my %aa_ref;
    while (my $newline = shift @{$content}) {
        chomp $newline;
        next unless ($newline =~ /^ATOM/);
        my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
            # Gli elementi del vettore da considerare sono
            # [1]   Atom serial number
            # [3]   Atom name
            # [4]   Alternate location indicator
            # [5]   Residue name
            # [7]   Chain identifier
            # [8]   Residue sequence number
            # [9]   Code for insertion of residues
            # [10-12] XYZ cpoordinates
            # [14]  Tfactor
        if ($splitted[3] =~ /^ CA $/) {
            my $resi = $splitted[5];
            my $chain = $splitted[7];
            my ($resn) = $splitted[8] =~ /(\d+)/;
            $aa_ref{$resn} = "$resi:$resn$chain";
        }
    }
    
    # leggo la CP matrix e la converto in in file csv
    $file_obj->set_filename($par->{'workdir'} . '/CP.matrix.dat');
    $content = $file_obj->read();
    my $csv_out = [ ];
    my %redundance_filter;
    while (my $newline = shift @{$content}) {
        chomp $newline;
        next unless $newline;
        my ($i,$j,$value) = split(/\s+/,$newline);
        if ($value > 0) {
            if ((exists $redundance_filter{"$i;$j"}) || (exists $redundance_filter{"$j;$i"})) {
                next;
            } else {
                $redundance_filter{"$i;$j"} = 1;
                push(@{$csv_out}, sprintf("%s;%s;%.3f\n", $aa_ref{$i}, $aa_ref{$j}, $value));
            }
        }
    }
    my $cpmatrix_file = $par->{'workdir'} . '/CP.matrix.csv';
    $file_obj->set_filename($cpmatrix_file);
    $file_obj->set_filedata($csv_out);
    $file_obj->write();
}

sub propensity {
    my $distance = $par->{'cp_cutoff'}; # questa dovrebbe essere la distanza per coprire un dominio
    printf("distance cutoff %i A\n", $distance);
    
    # raccolgo le coppie di residui che si trovano ad una distanza superiore a $distance
    my %pairs;
    $file_obj->set_filename($par->{'workdir'} . '/pairs.dat');
    $content = $file_obj->read();
    shift @{$content}; # rimuovo l'header
    while (my $newline = shift @{$content}) {
        chomp $newline;
        my @data = split(';', $newline);
        next if ($data[1] < $distance); # scarto le coppie a distanza inferiore
        my @pair = split('_', $data[0]);
        $pairs{$pair[0]} = { } unless (exists $pairs{$pair[0]});
        $pairs{$pair[0]}->{$pair[1]} = 1;
    }
    
    # raccolgo i valori di distance fluctuation per i residui i+4 e i-4
    $file_obj->set_filename($par->{'workdir'} . '/DF.matrix.dat');
    $content = $file_obj->read();
    my $df = [ ];
    foreach my $newline (@{$content}) {
        chomp $newline;
        next unless $newline;
        my ($a,$b,$value) = $newline =~ /^(\d+)\s*(\d+)\s*([\d\.\-]+)$/;
        if (abs($a-$b) <= 4) {
            push(@{$df}, $value);
        }
    }
    my $stat_obj = Statistics::Descriptive::Full->new();
    $stat_obj->add_data($df);
    my $threshold = $stat_obj->mean();
    printf("threshold DF value %.2f\n", $threshold);
    
    my %cps;
    my $cp_matrix = { }; my $maxvalue = 0E0;
    foreach my $newline (@{$content}) {
        chomp $newline;
        next unless $newline;
        my ($reference,$target,$value) = $newline =~ /^(\d+)\s*(\d+)\s*([\-\d\.]+)$/;
        $cps{$reference} = 0 unless (exists $cps{$reference});
        if ($value >= $threshold && exists($pairs{$reference}->{$target})) {
            $cp_matrix->{$reference}->{$target} = $value;
            $cp_matrix->{$target}->{$reference} = $value;
            $maxvalue = $value if ($value > $maxvalue);
            $cps{$reference}++;
        } elsif ((exists $cp_matrix->{$target}->{$reference}) || exists($cp_matrix->{$target}->{$reference})){
            next;
        } else {
            $cp_matrix->{$reference}->{$target} = 0E0;
        }
    }
    
    my ($tot_res) = qx/wc -l $par->{'workdir'}\/EIGENVAL.txt/;
    ($tot_res) = $tot_res =~ /^(\d+)/;
    
    # scrivo il file della matrice 
    $content = [ ];
    my @resi = keys %{$cp_matrix};
    @resi = sort {$a <=> $b} @resi;
    foreach my $i (@resi) {
        foreach my $j (@resi) {;
            if ($cp_matrix->{$i}->{$j}) {
                push(@{$content}, sprintf("%d  %d  %.6f\n", $i, $j, $cp_matrix->{$i}->{$j}));
            } else {
                push(@{$content}, sprintf("%d  %d  %.6f\n", $i, $j, 0E0));
            }
            
        }
        push( @{$content}, "\n" );
    }
    my $cpmatrix_file = $par->{'workdir'} . '/CP.matrix.dat';
    $file_obj->set_filename($cpmatrix_file);
    $file_obj->set_filedata($content);
    $file_obj->write();
    
    # plotto la matrice
    my $contrast = 1.50; # livello di contrasto
    my $cpmatrix_png = $par->{'workdir'} . '/CP.matrix.png';
    my $gnuscript = <<END
# 
# *** EMMA - Empathy Motions along fluctuation MAtrix ***
#
# Gnuplot script to draw flutuation matrix
# 
set terminal png size 2400, 2400
set output "$cpmatrix_png"
set size square
set pm3d map
# set palette rgbformulae 34,35,36
set palette defined ( 0 "white", 1 "orange", 2 "dark-red", 3 "black" ) # colori della palette
set cbrange[0 to $maxvalue/$contrast]
set tics out
set xrange[-1:$tot_res+2]
set yrange[-1:$tot_res+2]
set xtics 10
set xtics rotate
set ytics 10
set mxtics 10
set mytics 10
splot "$cpmatrix_file"
END
        ;
        my $gnuplot_file = $par->{'workdir'} . '/CP.matrix.gnuplot';
        $file_obj->set_filename($gnuplot_file);
        $file_obj->set_filedata([ $gnuscript ]);
        $file_obj->write();
        my $gplot_log = qx/$par->{'gnuplot'} $gnuplot_file 2>&1/;
#         print "\n$gplot_log"; # vedo cosa combina lo script in Gnuplot
    
    # scrivo il profilo della CP
    $file_obj->set_filename($par->{'workdir'} . '/CP.profile.dat');
    $content = [ ];
    foreach my $res (sort {$a <=> $b} keys %cps) {
        my $string = sprintf("%i  %.2f\n", $res, ($cps{$res}/$tot_res)*100);
        push(@{$content}, $string);
    }
    $file_obj->set_filedata($content);
    $file_obj->write();
    
    # plotto la distribuzione
    my $dist_png = $par->{'workdir'} . '/CP.profile.png';
    $gnuscript = <<END
# 
# *** EMMA - Empathy Motions along fluctuation MAtrix ***
#
# Gnuplot script to draw CP distribution
# 
set terminal png size 2400, 800
set size ratio 0.33
set output "$dist_png"
set key
set tics out
set xrange[0:$tot_res+1]
set xtics rotate
set xtics nomirror
set xtics 10
set mxtics 10
set xlabel "resID"
set yrange [0:100]
set ytics 20
set mytics 10
plot    "CP.profile.dat" with impulses lw 3 lc 0
END
    ;
    my $gnuscript_file = $par->{'workdir'} . '/CP.profile.gnuplot';
    $file_obj->set_filename($gnuscript_file);
    $file_obj->set_filedata([ $gnuscript ]);
    $file_obj->write();
    $gplot_log = qx/cd $par->{'workdir'};$par->{'gnuplot'} $gnuscript_file 2>&1/;
}

sub driven {
    my %selected_snapshots;
    
    RAGE: {
        my $rage_string = $par->{'RAGE'};
        $rage_string .= ' -file ../rmsd.xpm'
            unless ($rage_string =~ /\-file/);
        printf("RAGE command \"%s\"\n", $rage_string);
        my $cmd = "cd $par->{'workdir'}; $rage_string";
        qx/$cmd 2>&1/;
    }
    
    BEST_CLUSTERING: {
        $file_obj->set_filename($par->{'workdir'} . '/RAGE.cluster.log');
        $content = $file_obj->read();
        my $bestclust = 'null';
        my $mode = 'skip';
        while (my $newline = shift @{$content}) {
            ($newline =~ /^Optimal clustering is composed of/) and do {
                print "$newline";
                next;
            };
            ($newline =~ /^Best cluster is/) and do {
                chomp $newline;
                ($bestclust) = $newline =~ /Best cluster is (CLUSTER \d+)/;
                next;
            };
            ($newline =~ /^== $bestclust /) and do {
                print $newline;
                $mode = 'read';
                next;
            };
            ($mode eq 'read') and do {
                if ($newline =~ /^Average silhouette/) {
                    print $newline;
                } elsif ($newline =~ /^Best timeframe/) {
                    print $newline;
                } elsif ($newline =~ /^\[/) {
                    my ($list) = $newline =~ /([\d ]+)/;
                    my @timeframes = split('  ', $list);
                    while (my $singleframe = shift @timeframes) {
                        $selected_snapshots{$singleframe} = 1;
                    }
                } else {
                    $mode = 'skip';
                }
            };
            next;
        }
    }
    
    FILTERED_TRAJ: {
        # esporto una traiettoria completa
        my $cmd  = sprintf(
            "echo 3 | %s -f %s -s %s -o %s/traj.full.ca.pdb ",
            $par->{'trjconv'},
            $par->{'xtc_file'},
            $par->{'tpr_file'},
            $par->{'workdir'}
        );
        qx/$cmd 2>&1/;
        
        # filtro la traiettoria campionando solo i frame di interesse
        $/ = "ENDMDL\n";
        $file_obj->set_filename($par->{'workdir'} . '/traj.full.ca.pdb');
        $content = $file_obj->read();
        
        $/ = "\n";
        my $filtered = [ ];
        while (my $snapshot = shift @{$content}) {
            my ($timeframe) = $snapshot =~ /t=\s*(\d+)\.\d+/m;
            if (exists $selected_snapshots{$timeframe}) {
                push(@{$filtered}, $snapshot);
            }
        }
        $file_obj->set_filename($par->{'workdir'} . '/traj.ca.pdb');
        $file_obj->set_filedata($filtered);
        $file_obj->write;
    }
}

sub subset {
    # definisco il subset
    my ($start,$stop) = $par->{'filter'} =~ /^(\d+)-(\d+)$/;
    my %subset;
    foreach my $ok ($start..$stop) {
        $subset{$ok} = 1;
    }
    
    # leggo la traietoria campionata
    $file_obj->set_filename($par->{'workdir'} . '/traj.ca.pdb');
    $content = $file_obj->read();
    my $filtered = [ ];
    while (my $newline = shift @{$content}) {
        if ($newline =~ m/^ATOM /) { # parso solo la parte inerente le coordinate atomiche
            chomp $newline;
            my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
            my $resid = $splitted[1];
            $resid =~ s/ //g;
            next unless (exists $subset{$resid});
            $newline .= "\n";
        }
        push(@{$filtered},$newline);
    }
    
    # sovrascrivo la traietoria campionata
    $file_obj->set_filedata($filtered);
    $file_obj->write();
    
    printf("calculations will be performed onto the subset [%s]\n", $par->{'filter'});
}

sub samplecluster {
    my $cluster_log = $par->{'cluster_log'};
    $file_obj->set_filename($cluster_log);
    $content = $file_obj->read();
    
    my $cmd;
    
    # raccolgo gli snapshots del primo cluster e individuo il più rappresentativo
    my $reference;
    my @array;
    my $mode;
    my %first_cluster;
    while (my $newline = shift @{$content}) {
        chomp $newline;
        if ($newline =~ m/^  1 \|/) {
            ($reference) = $newline =~ m/^  1 \|[\s\d\.]+\|\s*(\d+)/; # lo snapshot rappresentativo
            $mode = 1;
        } elsif ($newline =~ m/^  2 \|/) {
            undef $mode;
        }
        next unless $mode;
        $newline =~ s/([ \.\d]+\|){3}//;
        push(@array, split(/\s+/, $newline));
    }
    @array = grep { /^\d+$/ } @array;
    while (my $snap = shift @array) { # gli altri snapshots del cluster
        $first_cluster{$snap} = 1;
    }
    
    print "reference snapshot for the 1st cluster: $reference\n";
    $cmd = sprintf(
        "echo 1 | %s -f %s -s %s -dump %s -o %s/reference.gro ",
        $par->{'trjconv'},
        $par->{'xtc_file'},
        $par->{'tpr_file'},
        $reference,
        $par->{'workdir'}
    );
    qx/$cmd 2>&1/;
    
    # faccio una RMSD relativa a quello snapshot
    $cmd = sprintf(
        "echo 3 3 | %s -f %s -s %s/reference.gro -o %s/rmsd.xvg ",
        $par->{'g_rms'},
        $par->{'xtc_file'},
        $par->{'workdir'},
        $par->{'workdir'}
    );
    qx/$cmd 2>&1/;
    
    # individuo gli snapshot di interesse (devono rientrare entro la soglia di RMSD e appartenere al primo cluster)
    my %framelist;
    my $threshold = $par->{'rmsd'};
    $file_obj->set_filename($par->{'workdir'} . '/rmsd.xvg');
    $content = $file_obj->read();
    my $discarded = 0E0;
    while (my $newline = shift @{$content}) {
        chomp $newline;
        next unless ($newline =~ /^\d+/);
        my ($frame,$rmsd) = $newline =~ /^([\d\.]+)\s*([\d\.]+)$/;
        if ($rmsd <= $threshold) {
            if (exists $first_cluster{int $frame}) {
                $framelist{int $frame} = sprintf("%.3f", $rmsd);
            } else {
#                 printf("frame %i (RMSD %.3f) out of cluster\n", int $frame, $rmsd);
                $discarded++;
            }
        }
    }
    printf("%i snapshot(s) found within %.3f RMSD\n", scalar keys %framelist, $threshold);
    printf("%i snapshot(s) found out of cluster\n", $discarded);
#     print Dumper \%framelist;
    
    # esporto una traiettoria completa
    $cmd  = sprintf(
        "echo 3 | %s -f %s -s %s -o %s/traj.full.ca.pdb ",
        $par->{'trjconv'},
        $par->{'xtc_file'},
        $par->{'tpr_file'},
        $par->{'workdir'}
    );
    qx/$cmd 2>&1/;
    
    # filtro la traiettoria campionando solo i frame di interesse
    $/ = "ENDMDL\n";
    $file_obj->set_filename($par->{'workdir'} . '/traj.full.ca.pdb');
    $content = $file_obj->read();
    $/ = "\n";
    my $filtered = [ ];
    while (my $snapshot = shift @{$content}) {
        my ($timeframe) = $snapshot =~ /t=\s*([\d\.]+)/m;
        if (exists $framelist{int $timeframe}) {
            push(@{$filtered}, $snapshot);
        }
    }
    $file_obj->set_filename($par->{'workdir'} . '/traj.ca.pdb');
    $file_obj->set_filedata($filtered);
    $file_obj->write;
}

sub total {
    my $ranges = $par->{'ranges'};
    
    # leggo la matrice delle fluttuazioni
    $file_obj->set_filename($par->{'workdir'} . '/DF.matrix.dat');
    $content = $file_obj->read();
    my $flumatrix = [ ];
    while (my $newline = shift(@{$content})) {
        chomp $newline;
        my ($i,$j,$flu) = $newline =~ m/(\d+)\s+(\d+)\s+([\d\-eE\.]+)/;
        next unless $flu; # righe non di interesse
        $flumatrix->[$i]->[$j] = $flu;
    }
    
    my $results = { };
    my ($mean, $stddev, $stat_obj);
    if (@{$ranges}) {
        while (my $range = shift(@{$ranges})) {
            my $label = sprintf("[%d:%d]", $range->[0], $range->[scalar(@{$range})-1]);
            $results->{$label} = [ ];
            my $data = [ ];
            for (my $i = 0; $i < scalar(@{$range}); $i++) {
                for (my $j = $i; $j < scalar(@{$range}); $j++) {
                    next if ($i == $j);
                    $flumatrix->[$range->[$i]]->[$range->[$j]] and do {
                        push(@{$data}, $flumatrix->[$range->[$i]]->[$range->[$j]]);
                    };
                }
            }
            
            if (scalar @{$data} > 0) {
                $stat_obj = Statistics::Descriptive::Full->new();
                $stat_obj->add_data($data);
                $mean = $stat_obj->mean();
                $stddev = $stat_obj->standard_deviation();
            } else {
                $mean = 0E0;
                $stddev = 0E0;
            }
            $results->{$label} = [ $mean, $stddev ];
        }
    } else {
        print "No range defined, skipping\n";
    }
    
    $file_obj->set_filename($par->{'workdir'} . '/DF.ave.csv');
    $content = [ "RANGE;MEAN;STDDEV\n" ];
    foreach my $range (sort keys %{$results}) {
        my $string = sprintf("%s;%.3f;%.3f\n", $range, $results->{$range}->[0], $results->{$range}->[1]);
        push(@{$content},$string);
    }
    $file_obj->set_filedata($content);
    $file_obj->write();
}

sub minimal {
    # numero totale dei residui
    my $tot_res = qx/wc -l $par->{'workdir'}\/EIGENVAL.txt/;
    ($tot_res) = $tot_res =~ /^(\d+)/;
    
    # leggo la lista degli autovalori
    my $eval = [ ];
    $file_obj->set_filename($par->{'workdir'} . '/EIGENVAL.txt');
    $content = $file_obj->read();
    for (my $i=0; $i < $tot_res; $i++) {
        my $value = shift @{$content};
        chomp $value;
        push(@{$eval}, $value);
    }
    # leggo la lista degli autovettori
    # ATTENZIONE: si interpreta come $evect->[n-esima_componente][n-esimo_autovettore]
    my $evect = [ ];
    $file_obj->set_filename($par->{'workdir'} . '/EIGENVECT.txt');
    $content = $file_obj->read();
    for (my $i=0; $i < $tot_res; $i++) {
        my $vect = shift @{$content};
        chomp $vect;
        $evect->[$i] = [ ];
        @{$evect->[$i]} = split(/\s+/, $vect);
    }
    
    # leggo la lista degli autovettori selezionati
    $file_obj->set_filename($par->{'workdir'} . '/which.txt');
    $content = $file_obj->read();
    my @quali;
    while (my $newline = shift @{$content}) {
        chomp $newline;
        push(@quali,$newline);
    }
    
    # matrice ricostruita sugli autovettori selezionati
    my $matrix = [ ]; 
    for (my $i=0; $i < $tot_res; $i++) { # inizializzo la matrice
        for (my $j=$i; $j < $tot_res; $j++) {
            $matrix->[$i] = [ ];
            $matrix->[$i][$j] = 0E0;
        }
    }
    # aggiorno la matrice
    my $elemento;
    foreach my $k (@quali) {
        for (my $i=0; $i < $tot_res; $i++) { # inizializzo la matrice
            for (my $j=$i; $j < $tot_res; $j++) {
                $elemento = $eval->[$k] * $evect->[$i][$k] * $evect->[$j][$k];
                $matrix->[$i][$j] += $elemento;
                $matrix->[$j][$i] += $elemento
                    unless ($i == $j);
            }
        }
    }
    
    # scrivo il file della matrice 
    $content = [ ];
    my $max = 0E0;
    my $value;
    for (my $i=0; $i < $tot_res; $i++) { # inizializzo la matrice
        for (my $j=0; $j < $tot_res; $j++) {
            $value = $matrix->[$i][$j];
            $max = $value if (($value > $max)&&(abs($i-$j) > 1));
            push( @{$content}, sprintf("%d  %d  %.6f\n", $i+1, $j+1, $value) );
        }
        push( @{$content}, "\n" );
    }
    my $emmatrix_file = $par->{'workdir'} . '/DF.matrix.dat';
    $file_obj->set_filename($emmatrix_file);
    $file_obj->set_filedata($content);
    $file_obj->write();
    
    # plotto la matrice
    my $contrast = 1.50; # livello di contrasto
    my $emmatrix_png = $par->{'workdir'} . '/DF.matrix.png';
    my $gnuscript = <<END
# 
# *** EMMA - Empathy Motions along fluctuation MAtrix ***
#
# Gnuplot script to draw flutuation matrix
# 
set terminal png size 2400, 2400
set output "$emmatrix_png"
set size square
set pm3d map
# set palette rgbformulae 34,35,36
set palette defined ( 0 "white", 1 "orange", 2 "dark-red", 3 "black" ) # colori della palette
set cbrange[0 to $max/$contrast]
set tics out
set xrange[-1:$tot_res+2]
set yrange[-1:$tot_res+2]
set xtics 10
set xtics rotate
set ytics 10
set mxtics 10
set mytics 10
splot "$emmatrix_file"
END
    ;
    my $gnuplot_file = $par->{'workdir'} . '/DF.matrix.gnuplot';
    $file_obj->set_filename($gnuplot_file);
    $file_obj->set_filedata([ $gnuscript ]);
    $file_obj->write();
    my $gplot_log = qx/$par->{'gnuplot'} $gnuplot_file 2>&1/;
#         print "\n$gplot_log"; # vedo cosa combina lo script in Gnuplot

}

sub distrib { 
    # distribuzione dei residui critici per ricostruire la matrice minimale
    
    # numero totale dei residui
    my $tot_res = qx/wc -l $par->{'workdir'}\/EIGENVAL.txt/;
    ($tot_res) = $tot_res =~ /^(\d+)/;
    my $threshold = sqrt ( 1 / $tot_res); # soglia per individuare gli hotspots
    
    # leggo la lista degli autovettori
    # ATTENZIONE: si interpreta come $evect->[n-esima_componente][n-esimo_autovettore]
    my $evect = [ ];
    $file_obj->set_filename($par->{'workdir'} . '/EIGENVECT.txt');
    $content = $file_obj->read();
    for (my $i=0; $i < $tot_res; $i++) {
        my $vect = shift @{$content};
        chomp $vect;
        $evect->[$i] = [ ];
        @{$evect->[$i]} = split(/\s+/, $vect);
    }
    
    # leggo la lista degli autovettori selezionati
    $file_obj->set_filename($par->{'workdir'} . '/which.txt');
    $content = $file_obj->read();
    my @quali;
    while (my $newline = shift @{$content}) {
        chomp $newline;
        push(@quali,$newline);
    }
    
    # @components è un vettore i cui elementi sono i valori massimi ottenuti di ogni componente tra gli autovettori scelti
    my @components = split(':', "0:" x $tot_res); # inizializzazione
    foreach my $k (@quali) {
        for (my $i=0; $i < $tot_res; $i++) {
            $components[$i] = abs($evect->[$i][$k])
                if (abs($evect->[$i][$k]) > abs($components[$i]));
        }
    }
    $content = [ ]; my $i = 1;
    foreach my $value (@components) {
        push(@{$content}, sprintf("%d  %.6f\n", $i, $value));
        $i++;
    }
    my $min = 0E0;my $max = 0E0;
    foreach my $value (@components) {
        $max = $value
            if ($value > $max);
        $min = $value
            if ($value < $min);
    }
    my $dist_file = $par->{'workdir'} . '/DF.profile.dat';
    $file_obj->set_filename($dist_file);
    $file_obj->set_filedata($content);
    $file_obj->write();
    
    # plotto la distribuzione
    $file_obj->set_filename($par->{'workdir'} . '/down');
    my $down = [ ]; $i = 1;
    foreach my $value (@components) {
        my $eval = $value;
        $eval = 0E0 if (abs($eval) > $threshold);
        push(@{$down}, sprintf("%d  %.6f\n", $i, $eval));
        $i++;
    }
    $file_obj->write('filedata' => $down);
    $file_obj->set_filename($par->{'workdir'} . '/up');
    my $up = [ ]; $i = 1;
    foreach my $value (@components) {
        my $eval = $value;
        $eval = 0E0 if (abs($eval) < $threshold);
        push(@{$up}, sprintf("%d  %.6f\n", $i, $eval));
        $i++;
    }
    $file_obj->write('filedata' => $up);
    my $dist_png = $par->{'workdir'} . '/DF.profile.png';
    my $gnuscript = <<END
# 
# *** EMMA - Empathy Motions along fluctuation MAtrix ***
#
# Gnuplot script to draw components distribution
# 
set terminal png size 2400, 800
set size ratio 0.33
set output "$dist_png"
set key
set tics out
set xrange[0:$tot_res+1]
set xtics rotate
set xtics nomirror
set xtics 10
set mxtics 10
set xlabel "resID"
set yrange [0:$max+0.1]
set ytics 0.1
set mytics 10
plot    "up" with impulses lw 3 lt 1, \\
        "down" with impulses lw 3 lt 3
END
    ;
    my $gnuscript_file = $par->{'workdir'} . '/DF.profile.gnuplot';
    $file_obj->set_filename($gnuscript_file);
    $file_obj->set_filedata([ $gnuscript ]);
    $file_obj->write();
    my $gplot_log = qx/cd $par->{'workdir'};$par->{'gnuplot'} $gnuscript_file 2>&1/;
#     print "\n$gplot_log"; # vedo cosa combina lo script in Gnuplot
}

sub forecast {
    my $block_dim = 10; # dimensione minima di un blocco, in residui
    my $overlap_thr = 0.50; # grado di sovrapposizione tra i blocchi, in percentuale
    my $coverage_thr = 0.75; # percentuale di compertura che si desidera raggiungere
    printf("internal parameters (see [%s])\n\$block_dim = %i; \$overlap_thr = %.2f; \$coverage_thr = %.2f\n", $0, $block_dim, $overlap_thr, $coverage_thr);
    
    my $tot_res = qx/wc -l $par->{'workdir'}\/EIGENVAL.txt/;
    ($tot_res) = $tot_res =~ /^(\d+)/;
    
    # numero massimo di autovettori su cui calcolare l'autocorrelazione; l'ideale sarebbe "$tot_res - 1", ma computazionalmente più impegnativo
    my $nmax = $tot_res - 1;
    
    # leggo la lista degli autovalori
    my $eval = [ ];
    $file_obj->set_filename($par->{'workdir'} . '/EIGENVAL.txt');
    $content = $file_obj->read();
    for (my $i=0; $i < $tot_res; $i++) {
        my $value = shift @{$content};
        chomp $value;
        push(@{$eval}, $value);
    }
    # leggo la lista degli autovettori
    # ATTENZIONE: si interpreta come $evect->[n-esima_componente][n-esimo_autovettore]
    my $evect = [ ];
    $file_obj->set_filename($par->{'workdir'} . '/EIGENVECT.txt');
    $content = $file_obj->read();
    for (my $i=0; $i < $tot_res; $i++) {
        my $vect = shift @{$content};
        chomp $vect;
        $evect->[$i] = [ ];
        @{$evect->[$i]} = split(/\s+/, $vect);
    }
    # estraggo le medie delle componenti dei primi nmax autovettori
    my $ave = [ ];
    for (my $n=0; $n < $nmax; $n++) {
        my $sum = 0E0;
        for (my $i = 0; $i < $tot_res; $i++) {
            $sum += $evect->[$i][$n];
        }
        push(@{$ave}, $sum/$tot_res);
    }
    # matrice di autocorrelazione
    my $corre = [ ];
    for (my $n = 0; $n < $nmax; $n++) {
        $corre->[$n] = [ ];
        for (my $i = 0; $i < $tot_res; $i++) {
            $corre->[$n][$i] = 0E0;
        }
    }
    # calcolo l'autocorrelazione del n-esimo autovettore
    for (my $n=0; $n < $nmax; $n++) {
        for(my $i = 0; $i < $tot_res-1; $i++) {
            my $corr = 0E0;
            my $norm = 0E0;
            for(my $j = $i+1; $j < $tot_res; $j++) {
                $corr += ( $evect->[$i][$n] - $ave->[$n] ) * ( $evect->[$j][$n] - $ave->[$n] );
                $norm += ( $evect->[$j][$n] - $ave->[$n] )**2;
            }
            $corr = $corr / $norm;
            if ($corr > 0) {
                $corre->[$n][$i] = 1;
            }
        }
    }
    shift @{$corre}; # butto via il primo autovettore (che tanto lo prendo di default)
    # creo una mappa di copertura
    my ($start, $stop);
    my %blocks;
    for (my $n=0; $n < scalar(@{$corre}); $n++) {
        my $label = sprintf("V%03d", $n+1);
        $blocks{$label} = [ ];
        
        for (my $i=0; $i < $tot_res; $i++) {
            if ($corre->[$n][$i] > 0) { # ho trovato un blocco
                next if $start;
                $start = $i + 1;
            } else { # ho raggiunto la fine di un blocco
                next unless $start;
                $stop = $i;
            }
            if ($start && $stop) {
                if (($stop - $start) >= $block_dim) {
                    my $range = "$start\_$stop";
                    push(@{$blocks{$label}}, $range);
                }
                $start = 0;
                $stop = 0;
            }
        }
    }
    # filtro di ridondanza (un autovettore è non ridondante se possiede almeno un blocco che non si sovrappone con quelli degli autovettori precedenti)
    my %selected_eigenvect;
    my @coverage = split(':', "0:" x $tot_res);
    foreach my $label (sort keys %blocks) {
        my @array = @{$blocks{$label}};
#         printf("\n---\n%s => [ %s ]\n  selected blocks: ", $label, join(' ', @array));
        next unless @array;
        my $retain = 0E0;
        while (my $block = shift @array) {
            ($start,$stop) = $block =~ /(\d+)_(\d+)/;
            $start--;
            my $range = $stop - $start;
            my $overlap = 0E0;
            for (my $i=$start; $i <= $stop; $i++) {
                $overlap++ if ($coverage[$i] > 0);
            }
            if (($overlap/$range) < $overlap_thr) {
#                 printf("[%d_%d] ", $start+1, $stop);
                $retain = 1;
                for (my $i=$start; $i < $stop; $i++) {
                    $coverage[$i] = 1;
                }
            }
        }
        if ($retain > 0) {
            $selected_eigenvect{$label} = sprintf( "%s", join('', @coverage));
        }
    }
    
    # statistiche di copertura
    print "eigenvectors cumulative coverage:\n";
    foreach my $ev (sort keys %selected_eigenvect) {
        my $string = $selected_eigenvect{$ev};
        my $tot_res = length $string;
        my $coverage = $string =~ y/1/2/;
        $coverage = sprintf("%.3f", $coverage/$tot_res);
        $selected_eigenvect{$ev} = $coverage;
        printf("[%s] %s%%\n", $ev, $coverage * 100);
    }
    
    # preparo la lista degli autovettori selezionati
    $content = [ ];
    push(@{$content}, "0\n"); # il primo lo prendo ad occhi chiusi
    foreach my $ev (sort keys %selected_eigenvect) {
        if ($selected_eigenvect{$ev} <= $coverage_thr) {
            my ($which) = $ev =~ /^V[0]*(\d+)$/;
            push(@{$content}, "$which\n");
        }
    }
    $file_obj->set_filename($par->{'workdir'} . '/which.txt');
    $file_obj->set_filedata($content);
    $file_obj->write();
}

sub diago {
    my $matrix_file = $par->{'workdir'} . '/flu_matrix.csv';
    my $eval_file = $par->{'workdir'} . '/EIGENVAL.txt';
    my $evect_file = $par->{'workdir'} . '/EIGENVECT.txt';
    my $scRipt = <<END
# IMPORTO LA MATRICE
flu.mat <- as.matrix(read.csv("$matrix_file", header = FALSE, sep = ";", row.names = NULL, stringsAsFactors = FALSE, dec = ".")) # importo la matrice delle fluttuazioni
# DIAGONALIZZO
diago <- eigen(flu.mat, symmetric = TRUE)
# AUTOVALORI
eval <- diago\$values
write.table(eval, file = "$eval_file", quote = FALSE, row.names = FALSE, col.names = FALSE, sep = ",", dec = ".")
# AUTOVETTORI
evec <- as.data.frame(diago\$vectors)
write.table(evec, file = "$evect_file", quote = FALSE, row.names = FALSE, col.names = FALSE, sep = "\t", dec = ".")
END
    ;
    my $R_file = $par->{'workdir'} . '/pca.R';
    $file_obj->set_filename($R_file);
    $file_obj->set_filedata([ $scRipt ]);
    $file_obj->write();
    my $log = qx/cd $par->{'workdir'};$par->{'R'} $R_file 2>&1/;
#     print "\n<<$log>>"; # vedo cosa combina lo script in R
}

sub flumat {
    # carico in memoria la traiettoria
    my $traj = { };
    $file_obj->set_filename($par->{'workdir'} . '/traj.ca.pdb');
    $content = $file_obj->read();
    my ($model_num, $res_num);
    while (my $newline = shift @{$content}) {
        chomp $newline;
        $newline =~ /^MODEL/ and do { # leggo il frame della traiettoria
            ($model_num) =  $newline =~ /^MODEL\s+(\d+)/;
            $model_num = sprintf("MODEL_%05d", $model_num);
            $traj->{$model_num} = [ ];
            $res_num = 1;
            next;
        };
        $newline =~ /^ATOM/ and do { # leggo le coordinate atomiche associate al frame
            my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
            # Gli elementi del vettore @splitted da considerare sono:
            #   [3]   Atom name
            #   [11-13] XYZ coordinates
            next unless ($splitted[3] eq ' CA '); # x il momento considero solo le coord dei C-alpha
            for (my $i = 0; $i < scalar @splitted; $i++) {
                $splitted[$i] =~ s/\s+//g;
            }
            $traj->{$model_num}->[$res_num] = [ $splitted[11], $splitted[12], $splitted[13] ];
            $res_num++;
        };
    }
    
    # carico in memoria la matrice delle distanze medie
    my $ave = { };
    $file_obj->set_filename($par->{'workdir'} . '/pairs.dat');
    $content = $file_obj->read();
    shift @{$content}; # rimuovo l'header
    while (my $newline = shift @{$content}) {
        chomp $newline;
        my ($pair,$mean,$stddev) = split(';', $newline);
        $ave->{$pair} = $mean;
    }
    
    # Signal-to-Noise Ratio: siccome voglio individuare le coppie di atomi che si muovono meno userò questa misura della fluttuazione.
    my $flumatrix = { };
    my @frames = sort keys %{$traj};
    my ($atom_i, $atom_j, $distance, $ave_diff, $mean, $stddev, $data, $stat_obj, $pair);
    my $maxvalue = 0E0;
    for (my $i = 1; $i < scalar @{$traj->{$frames[0]}}; $i++) {
        for (my $j = $i; $j < scalar @{$traj->{$frames[0]}}; $j++) {
            $data = [ ]; # inizializzo il vettore contenente i dati
            $pair = "$i\_$j";
            foreach my $frame (@frames) {
                $atom_i = $traj->{$frame}->[$i];
                $atom_j = $traj->{$frame}->[$j];
                $distance = sqrt( ($atom_i->[0] - $atom_j->[0])**2 + ($atom_i->[1] - $atom_j->[1])**2 + ($atom_i->[2] - $atom_j->[2])**2 );
                $ave_diff = ($distance - $ave->{$pair})**2;
                push(@{$data},$ave_diff);
            }
            $mean = $ave->{$pair};
            my $summa = 0E0; ($summa+=$_) for @{$data};
            $stddev = sqrt ( $summa / scalar @frames );
            unless ($stddev) {
                $flumatrix->{$pair} = 0E0;
            } else {
                $flumatrix->{$pair} = $mean / $stddev;
            }
            $maxvalue = $flumatrix->{$pair} if ($flumatrix->{$pair} > $maxvalue);
        }
    }
    
    # filtro per residui contigui
    my $window = 1; # definizione di "contiguo" (i-j < $window)
    printf("adjacent pairs within a range of %d residue(s) (see [%s])\n", $window, $0);
    printf("filtering adjacent pairs to coordination value %.3f\n", $maxvalue);
    foreach my $pair (sort keys %{$flumatrix}) {
        my ($i, $j) = $pair =~ m/(\d+)_(\d+)/;
        next if (abs($i - $j) > $window);
        $flumatrix->{$pair} = $maxvalue;
    }
    
    
    # scrivo il file della matrice
    $content = [ ];
    my $key;
    for (my $i = 1; $i < scalar @{$traj->{$frames[0]}}; $i++) {
        my $newline = '';
        for (my $j = 1; $j < scalar @{$traj->{$frames[0]}}; $j++) {
            $key = "$i\_$j";
            $key = "$j\_$i" unless(exists $flumatrix->{$key});
            $newline .= sprintf("%.3f;", $flumatrix->{$key}); 
        }
        $newline =~ s/;$/\n/;
        push(@{$content}, $newline);
    }
    $file_obj->set_filename($par->{'workdir'} . '/flu_matrix.csv');
    $file_obj->set_filedata($content);
    $file_obj->write();
}

sub ave {
    # carico in memoria la traiettoria
    my $traj = { };
    
    $file_obj->set_filename($par->{'workdir'} . '/traj.ca.pdb');
    $content = $file_obj->read();
    my ($model_num, $res_num);
    while (my $newline = shift @{$content}) {
        chomp $newline;
        $newline =~ /^MODEL/ and do { # leggo il frame della traiettoria
            ($model_num) =  $newline =~ /^MODEL\s+(\d+)/;
            $model_num = sprintf("MODEL_%05d", $model_num);
            $traj->{$model_num} = [ ];
            $res_num = 1;
            next;
        };
        $newline =~ /^ATOM/ and do { # leggo le coordinate atomiche associate al frame
            my @splitted = unpack('Z6Z5Z1Z4Z1Z3Z1Z1Z4Z1Z3Z8Z8Z8Z6Z6Z4Z2Z2', $newline);
            # Gli elementi del vettore @splitted da considerare sono:
            #   [3]   Atom name
            #   [11-13] XYZ coordinates
            next unless ($splitted[3] eq ' CA '); # x il momento considero solo le coord dei C-alpha
            for (my $i = 0; $i < scalar @splitted; $i++) {
                $splitted[$i] =~ s/\s+//g;
            }
            $traj->{$model_num}->[$res_num] = [ $splitted[11], $splitted[12], $splitted[13] ];
            $res_num++;
        };
    }
    
    # calcolo la distanza media per ogni coppia di C-alpha
    my @frames = sort keys %{$traj};
    my ($atom_i, $atom_j, $distance, $mean, $stddev, $data, $stat_obj);
    $content = [ "PAIR;MEAN;STDDEV\n" ];
    for (my $i = 1; $i < scalar @{$traj->{$frames[0]}}; $i++) {
        for (my $j = $i; $j < scalar @{$traj->{$frames[0]}}; $j++) {
            $data = [ ]; # inizializzo il vettore contenente i dati
            foreach my $frame (@frames) {
                $atom_i = $traj->{$frame}->[$i];
                $atom_j = $traj->{$frame}->[$j];
                $distance = sqrt( ($atom_i->[0] - $atom_j->[0])**2 + ($atom_i->[1] - $atom_j->[1])**2 + ($atom_i->[2] - $atom_j->[2])**2 );
                push(@{$data},$distance);
            }
            $stat_obj = Statistics::Descriptive::Full->new();
            $stat_obj->add_data($data);
            $mean = $stat_obj->mean();
            $stddev = $stat_obj->standard_deviation();
            push(@{$content}, sprintf("%s_%s;%.3f;%.3f\n", $i, $j, $mean, $stddev));
        }
    }
    
    $file_obj->set_filename($par->{'workdir'} . '/pairs.dat');
    $file_obj->set_filedata($content);
    $file_obj->write();
}

sub sampling {
    my $xtc_file = $par->{'xtc_file'};
    my $tpr_file = $par->{'tpr_file'};
    foreach my $file ($xtc_file, $tpr_file) {
        croak "\nE- file [$file] not found\n\t" unless (-e $file);
    }
    
    # conto il numero di frames totali e divido per quelli richiesti in input
    my $gmxcheck = $par->{'gmxcheck'};
    my $log = qx/$gmxcheck -f $xtc_file 2>&1/;
    my ($tot_frames) = $log =~ /Last frame\s+(\d+)/g;
    my $skip = int ($tot_frames/$par->{'sample_size'});
    
    # campiono la traiettoria per i Calpha in formato pdb 
    my $string;
    if ($skip == 0) {
        $string = sprintf(
            "echo 3 | %s -f %s -s %s -o %s/traj.ca.pdb ",
            $par->{'trjconv'},
            $xtc_file,
            $tpr_file,
            $par->{'workdir'}
        );
    } else {
        $string = sprintf(
            "echo 3 | %s -f %s -s %s -skip %s -o %s/traj.ca.pdb ",
            $par->{'trjconv'},
            $xtc_file,
            $tpr_file,
            $skip,
            $par->{'workdir'}
        );
    }
    qx/$string 2>&1/;
#     system $string;
    printf("%i snapshot(s) skipping %.2f timeframes\n", $par->{'sample_size'}, $skip)
}

sub clock {
    my ($sec,$min,$ore,$giom,$mese,$anno,$gios,$gioa,$oraleg) = localtime(time);
    $mese = $mese+1;
    $mese = sprintf("%02d", $mese);
    $giom = sprintf("%02d", $giom);
    $ore = sprintf("%02d", $ore);
    $min = sprintf("%02d", $min);
    $sec = sprintf("%02d", $sec);
    my $date = '[' . ($anno+1900)."/$mese/$giom $ore:$min:$sec]";
    return $date;
}