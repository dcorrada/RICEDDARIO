Riscrivere il README aggiungendo le dipendenze per i pacchetti aggiuntivi:


Installation
The SQLite3 can be integrated with Perl using Perl DBI module, which is a database access module for the Perl programming language. It defines a set of methods, variables and conventions that provide a standard database interface.

Here are simple steps to install DBI module on your Linux/UNIX machine:

    $ wget http://bo.mirror.garr.it/mirrors/CPAN/authors/id/T/TI/TIMB/DBI-1.631.tar.gz
    $ tar xvfz DBI-1.631.tar.gz
    $ cd DBI-1.631
    $ perl Makefile.PL
    $ make
    $ make install

If you need to install SQLite driver for DBI, then it can be installed as follows:

    $ wget http://bo.mirror.garr.it/mirrors/CPAN//authors/id/I/IS/ISHIGAKI/DBD-SQLite-1.42.tar.gz
    $ tar xvfz DBD-SQLite-1.42.tar.gz
    $ cd DBD-SQLite-1.42
    $ perl Makefile.PL
    $ make
    $ make install

