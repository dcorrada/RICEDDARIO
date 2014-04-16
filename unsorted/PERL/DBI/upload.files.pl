#!/usr/bin/perl -w
use strict;
use DBI;

=head1 NAME

blobs.pl -- script to upload / download HUGE BLOB fields 
to a MySQL database

=head1 SYNOPSIS

For the purpose of this tutorial, this script will create
a B<software repository>, where you can upload binary packages,
list their status and download them to a file.


 $ perl blobs.pl u perl perl_stable.tar.gz "5.6.1" "my latest version"

Uploads the perl binary package (> 5 MB) to a database table, 
splitting the file into chunks if necessary

 $ perl blobs.pl l perl

Lists the details of the "perl" package stored in the database

 $ perl blobs.pl d perl perl_stable.5.6.1.tgz

Downloads the perl binary and saves it to a new file

=head1 The script

=head2 parameters

    u|d|l|r = (u)pload | (d)ownload | (l)ist | (r)emove

    name  = the name of the package that we want to upload / download 
            / list. In the latter case, you can use DB wildchars 
            ('%' = any sequence of chars, '_' = any character)

    filename = the name of the file to upload / download. Mandatory 
            only for uploading. If missing when we download, the
            name stored in the database is used.

    version = free text up to 12 characters
    
    description = free text up to 250 characters
    
=head2 Status of this script 

This script is mainly provided for tutorial purposes. Although 
it works fine, it is not as robust as I would like it to be. 
I am planning to make a module out of it, to isolate the data 
management from the interface. Eventually I will do it. 
In the meantime, please forgive my hasty interface and try to 
concentrate on the theory behind it. Thanks.

=head2 handling parameters

Nothing fancy. Interface to a minimum. Parameters are read
sequencially from the command line. Optional parameters are
evaluated according to the current operation.

=cut


my $op = shift or help(); # operation (list / upload/download)
help() unless $op =~ /^[udlr]$/;
my $softname = shift or help(); # package name
my ($filename, $version, $description)=(undef,undef,undef);

if ($op eq "u") { # read optional parameters
    $filename = shift or help();
    $version = shift;
    $description = shift;
}
elsif ($op eq "d") {
    $filename = shift;
}

=head2 connection

If this were a module, you would have to pass an already 
constructed $dbh object. Since it is a script, instead,
you should modify the statement to suit your needs.
Don't forget to create a "software" database in your
MySQL system, or change the name to a more apt name.

=cut

my $dbh = DBI->connect("DBI:mysql:software;host=localhost;"
            . "mysql_read_default_file=$ENV{HOME}/.my.cnf", 
            undef,undef, {RaiseError => 1});

=head2 Table structure

The table is created the first time the script is executes,
unless it exists already.

=cut
            
#$dbh->do(qq{CREATE DATABASE IF NOT EXISTS software});

$dbh->do(qq{CREATE TABLE IF NOT EXISTS software_repos 
    (id INT not null auto_increment primary key,
    name varchar(50) not null,
    description varchar(250),
    vers varchar(15),
    bin mediumblob,
    filename varchar(50) not null,
    username varchar(30) not null,
    updated timestamp(14) not null,
    key name(name),
    unique key idname (id, name)
    )});

=head2 scrip flow

depending on th value of $op (operation) the appropriate
subroutine is called.

=cut

    
if ($op eq "l") {
    list($softname);
}
elsif ($op eq "u") {
    upload($softname, $filename, $version, $description)
}
elsif ($op eq "r") {
    remove($softname);
}
else {
    download($softname, $filename)
}

$dbh->disconnect();

=head2 functions

=over 4

=item getlist()

getlist() gets the details of a given package stored in
the database and returns a reference to an array reference
with the selected table information.

=cut

sub getlist{
    my $sname = shift;
    my $row = $dbh->selectall_arrayref(qq{
        select name, vers, count(*) as chunks,
        sum(length(bin)) as size, filename, description 
        from software_repos
        where name like "$sname"
        group by name
    });
    # the GROUP BY clause is necessary to give the total 
    # number of chunks and the total size 
    return $row; 
}

=item list

list() calls internally getlist() and prints the result

=cut


sub list {
    my $sname = shift;
    my $row = getlist($sname);
    return undef unless $row->[0];
    print join "\t", qw(name ver chunks size filename 
        description),"\n";
    print '-' x 60, "\n";
    print join "\t", @{$_},"\n" for @$row;
}

=item remove

remove() will delete an existing package from the
database table.
Nothing happens if the package does not exist.

=cut

sub remove {
    my $sname = shift;
    $dbh->do(qq{ delete from software_repos
        where name = "$sname"});
}
    
=item upload

upload() reads a given file, in chunks not larger than
the value of max_allowed_packet, and store them into
the database table.

=cut

sub upload {
    my ($sname, $fname, $vers, $descr) = @_;
    open FILE, "< $fname" or die "can't open $fname\n";
    my $maxlen = getmaxlen(); # gets the value of max_allowed_packet
    my $bytes=$maxlen;
    $fname =~ s{.*/}{}; # removes the path from the file name
    print "$fname\n";
    my $sth = $dbh->prepare(qq{
        INSERT INTO software_repos 
        (name, vers, bin, description, filename, username, updated) 
            VALUES ( ?, ?, ?, ?, ?, user(), NULL)});
    
    # before uploading, we delete the package with the same name
    remove($sname);
    # now we read the file and upload it piece by piece
    while ($bytes) {
        read FILE, $bytes,$maxlen;
        $sth->execute( $sname, $vers, $bytes, $descr, $fname) 
            if $bytes;
    }
    close FILE;
}
    
=item download

download() is upload() counterpart. It fetches the chunks from
the database and compose a new binary file.

=cut

sub download {
    my ($sname, $fname) = @_;
    # if we don't supply a name, the one stored in
    # the database will be used
    unless (defined $fname) {
        my $row = getlist($sname);
        die "$sname not found\n" unless $row->[0];  
        $fname =$row->[0][4];
    }
    # checks if the file exists. Refuses to overwtite
    if (-e $fname) {
        die "file ($fname) exists already\n";
    }
    open FILE, "> $fname" or die "can't open $fname\n";
    my $sth = $dbh->prepare(qq{
         SELECT  bin 
            from software_repos
            where name = ?
            order by id
        });
    $sth->execute($sname);
    my $success =0;
    while (my @row = $sth->fetchrow_array()) {
        syswrite FILE, $row[0];
        $success =1;
    }
    close FILE;
    die "$sname not found\n" unless $success;
}

=item getmaxlen

getmaxlen() will return the value of max_allowed_packet

=cut

sub getmaxlen {
    my $rows = $dbh->selectall_arrayref(
       qq{show variables LIKE "max_allowed_packets"});
    for (@$rows) {
        # returns the max_allowed_packet
        # minus a safely calculated size
        return $_->[1] - 100_000 
    }
    die "max packet length not found \n";
}

=item help

help() gives a summary of the script usage

=back

=cut

sub help {
print <<HELP;
usage: blobs {l|u|d|r} name [[filename] [version] [description]]
Where l|u|d|r is the operation (list|upload|download|remove)
    name is the name of the software to be uploaded|downloaded
    filename is the file to send to the database (upload)
    or where to save the blob (download).
    Optionally, you can supply a version and a description 
HELP

exit;
}
