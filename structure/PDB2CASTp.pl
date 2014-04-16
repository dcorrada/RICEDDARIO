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
use LWP::UserAgent;
use Mail::IMAPClient;
use MIME::Parser;


## GLOBS ##
our $homedir = $ENV{HOME};
our $workdir = getcwd();
our $proberad = 1.4; # probe radius, in Angstrom
our $castp_url = 'http://sts.bioengr.uic.edu/castp/advcal.php';
our %email;
our @pdb_list;
our $hetatom;
## SBLOG ##

USAGE: {
    print "*** PDB2CASTp ***\n";
    
    my $help;
    use Getopt::Long;no warnings;
    GetOptions('h' => \$help, 'p=f{1}' => \$proberad, 'l' => \$hetatom);
    my $usage = <<END

********************************************************************************
PDB2CASTp
release 14.3.lbpc7

Copyright (c) 2011-2014, Dario CORRADA <dario.corrada\@gmail.com>


This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

    This script submit in batch a list of PDB files (stored in pwd path) to 
    CASTp server.

SYNOPSYS

    PDB2CASTp.pl [option] submit|fetch [mail.conf]

CONF FILE
    
    Required both in submit and fetch mode, the conf file must be compiled as
    in the following example:
    
        address   = foo\@bar.com,
        username  = foo,
        password  = baz,
        server    = imap.bar.com,
        port      = 993'
    
MODES
    
    submit      batch submission of a list of PDB files (stored in pwd path)
    
    fetch       access an IMAP mail-server and download the messages sent from
                CASTp server
    
OPTIONS
    
    -p <float>  [submit mode] probe radius, CASTp server accepts only values 
                between 0.0 and 10.0 Angstrom (default: 1.4)
    
    -l          [submit mode] include HET groups in the calculation and run
                calculations, the PDB input files must contain the HET flags for
                each heteroatom to be considered (see NOTES)
    
NOTES
    The HET flags have to be edited with the following format, according to the 
    PDB format description guide v3.30:
    
    ----------------------------------------------------------------------------
    COLUMNS         DATA TYPE       FIELD           DEFINITION
    ----------------------------------------------------------------------------
    1 - 6           String(6)       Record name     "HET", left justified
    
    8 - 10          String(3)       hetID           Het identifier, right 
                                                    justified
    
    13              Character       ChainID         Chain identifier
    
    14 - 17         Integer         seqNum          Sequence number, right
                                                    justified
    
    18              AChar           iCode           Insertion code
    
    21 - 25         Integer         numHetAtoms     Number of HETATM records,
                                                    left justified
    
    31 - 70         String          text            Text describing Het group,
                                                    left justified
    ----------------------------------------------------------------------------
    
    Just below an example of string, '.' are space characters:
    
        HET....UNK..C.470...22........dioxine................................
END
    ;
    
    $help and do { print $usage; goto FINE; };
}

INIT: {
    my $mode = $ARGV[0];
    my $conf_file = $ARGV[1];
    
    if ($conf_file) {
        open(CONF, '<' . $conf_file) or croak("E- unable to open <$conf_file>\n\t");
        while (my $newline = <CONF>) {
            chomp $newline;
            my ($key,$value) = $newline =~ m/(\w+)\s*=\s*(.+)/;
            $email{$key} = $value;
        }
        close CONF;
    } elsif (-e ($homedir . '/.PDB2CASTp.conf')){
        $conf_file = $homedir . '/.PDB2CASTp.conf';
        open(CONF, '<' . $conf_file) or croak("E- unable to open <$conf_file>\n\t");
        while (my $newline = <CONF>) {
            chomp $newline;
            my ($key,$value) = $newline =~ m/(\w+)\s*=\s*(.+)/;
            $email{$key} = $value;
        }
        close CONF;
    } else {
        my $ans;
        print "\nNo e-mail account configured yet, do you want to proceed? [y/N] ";
        $ans = <STDIN>; chomp $ans;
        goto FINE unless ($ans eq 'y');
        $conf_file = $homedir . '/.PDB2CASTp.conf';
        print "MAIL ADDRESS...: ";
        $email{'address'} = <STDIN>; chomp $email{'address'};
        print "USER NAME......: ";
        $email{'username'} = <STDIN>; chomp $email{'username'};
        print "PASSWORD.......: ";
        $email{'password'} = <STDIN>; chomp $email{'password'};
        print "IMAP SEVER.....: ";
        $email{'server'} = <STDIN>; chomp $email{'server'};
        print "PORT...........: ";
        $email{'port'} = <STDIN>; chomp $email{'port'};
        open(CONF, '>' . $conf_file) or croak("E- unable to open <$conf_file>\n\t");
        foreach my $key (keys %email) {
            print CONF "$key = $email{$key}\n";
        }
        close CONF;
    }
    
    unless ($mode) {
        print "\nnothing to do, aborting";
        goto FINE;
    } elsif ($mode eq 'submit') {
        goto READPDB;
    } elsif ($mode eq 'fetch') {
        goto MAIL;
    } else {
        print "\nundef mode, aborting";
        goto FINE;
    }
}

READPDB: { # mi salvo in un array la lista di file PDB
    printf("\n%s retrieving PDB file list...", clock());
    my $dh;
    opendir ($dh, $workdir) or croak("\nE- unable to open <$workdir>\n\t");
    my @all_file_list = readdir($dh);
    closedir $dh;
    @pdb_list = grep /\.pdb$/, @all_file_list;
    @pdb_list = map { $workdir . '/' . $_ } @pdb_list;
}

REQUEST: { # sottomissione al server
    foreach my $input_file (@pdb_list) {
        printf("\n%s submitting <%s> to CASTp server...", clock(), $input_file);
        my $jobid;
        my $bot = LWP::UserAgent->new();
        $bot->agent('libwww-perl/5.805');
        $bot->timeout(600);
        my $request;
        if ($hetatom) {
            $request = $bot->post( $castp_url,
                Content_type => 'multipart/form-data',
                Content => [
                    email     => "$email{'address'}",
                    pradius2  => "$proberad",
                    visual    => 'emailonly',
                    # flags per sottomettere un file locale
                    submit_file => "Submit",
                    userfile  => [ "$input_file" ],
                    hetopt    => 'on'
                    # flags per reperire pdb precalcolati
#                     submit_pdb => "Submit",
#                     pdbid  => "1fkf"
                ]
            );
            # CASTp passa per una pagina intermedia in cui chiede conferma per la
            # selezione di catene e ligandi, di default lacio che processi tutto
            my ($hetpath) = $request->{'_headers'}->{'location'} =~ m/^\.(.*)/;
            $hetpath = "http://sts.bioengr.uic.edu/castp" . $hetpath;
            my $get_page = $bot->get($hetpath);
            my %params;
            foreach my $newline (split('\n', $get_page->content)) {
                chomp $newline;
                if ($newline =~ /<input type='/) {
                    my ($key, $value) = $newline =~ /name='(.+)'\s*value='(.*)'/;
                    $params{$key} = $value;
                }
            }
            $params{'pdbid'} = '';
            $request = $bot->post( 'http://sts.bioengr.uic.edu/castp/modify_file.php',
                Content_type => 'multipart/form-data',
                Content => [ %params ]
            );
            ($jobid) = $params{'file'} =~ m/uploads\/(.*)/;
        } else {
            $request = $bot->post( $castp_url,
                Content_type => 'multipart/form-data',
                Content => [
                    email     => "$email{'address'}",
                    pradius2  => "$proberad",
                    visual    => 'emailonly',
                    # flags per sottomettere un file locale
                    submit_file => "Submit",
                    userfile  => [ "$input_file" ]
                    # flags per reperire pdb precalcolati
#                     submit_pdb => "Submit",
#                     pdbid  => "1fkf"
                ]
            );
        }
        # Una volta sottomesso un job il server CASTp butta fuori una pagina di notifica, che deve essere caricata il job venga sottomesso
        my ($token) = $request->{'_headers'}->{'location'} =~ m/^\.(.*)/;
        $token = "http://sts.bioengr.uic.edu/castp" . $token;
        my $get_token = $bot->get($token);
        unless ($hetatom) {
            ($jobid) = $token =~ m/uploads\/(\w*)&/;
        }
        printf(" %s", $jobid);
    }
    printf("\n%s request(s) sent at <%s>", clock(), $email{'address'});
    goto FINE;
}

MAIL: {
    printf("\n%s connecting to <%s:%s>", clock(), $email{'server'}, $email{'port'});
    my $imap = new Mail::IMAPClient(
        User     => "$email{'username'}",
        Password => "$email{'password'}",
        Server   => "$email{'server'}",
        Port     => "$email{'port'}",
        Ssl      => 1,
    ) or croak("\nE- connection failed\n\t");
    printf("\n%s <%s> authenticated", clock(), $email{'username'}) if $imap->IsAuthenticated();
    # lista delle cartelle
#     my $folders = $imap->folders;
#     print Dumper $folders;
    $imap->select("INBOX") or croak(sprintf("\nE- %s\n\t", $imap->LastError)); # seleziona la posta in arrivo
    $imap->Uid(1);
    my @msg = $imap->messages or croak("\nE- unable to retrieve messages\n\t");;
    my $jobcount = 0E0;
    foreach my $message (@msg) {
        my $subj = $imap->subject($message);
        unless ($subj) {
            carp("\nW- Unable to check message [$message], skipping\n\t");
            next;
        }
        if ($subj =~ /CASTp calculation/) {
            my $body = $imap->body_string($message);
            my ($jobid) = $body =~ m/zipped into (\w+)\.tar\.gz/g;
            printf("\n%s retrieving job %s...", clock(), $jobid);
            my $parser = MIME::Parser->new;
            $parser->output_dir($workdir);
            # di default il parser salva mail e attachments in due file separati
            my $entity = $parser->parse_data($imap->message_string($message));
            # elimino il messaggio dalla casella di posta
#             $imap->delete_message($message);
            $jobcount++;
        }
    }
    # chiudo la cartella e mi dsconnetto
    $imap->close or croak(sprintf("\nE- %s\n\t", $imap->LastError));;
    $imap->logout or croak(sprintf("\nE- %s\n\t", $imap->LastError));;
    printf("\n%s %i jobs fetched", clock(), $jobcount);
}

FINE: {
    print "\n\n*** pTSAC2BDP ***\n";
    exit;
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