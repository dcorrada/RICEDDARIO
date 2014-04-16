#!/opt/perl51/bin/perl
# -d

use strict;
use warnings;

use Net::SMTP;

# definisco l'host SMTP
my $smtp = Net::SMTP->new('mail.mi.cnr.it');

# $smtp->auth('dcorrada-itb', 'yjr9171');

$smtp->mail('dario.corrada@itb.cnr.it');
$smtp->to('dario.corrada@gmail.com');

$smtp->data();
$smtp->datasend("Subject: Ciao, ti invio una cartolina virtuale.\n");
$smtp->datasend("To: gmail\n");
$smtp->datasend("From: itb\n");
$smtp->datasend("\ncontenuto");
$smtp->dataend();

$smtp->quit;


print "\n_____________\nFINE PROGRAMMA\n";
exit;