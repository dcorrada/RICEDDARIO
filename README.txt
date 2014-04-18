********************************************************************************
RICEDDARIO
Copyright (c) 2006-2014, Dario Corrada <dario.corrada@gmail.com>

Some of the script contained in the subdirectories are covered by separate 
licenses; see the individual headers for more information.

Whenever not explicitly mentioned the scripts are licensed under a 
Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

The RICEDDARIO package is a comprehensive package of all my script.

--- DEPENDENCIES ---

Some scripts require specific third party software that are not provided with
the RICEDDARIO package and therefore require to be pre-installed. Maybe some of 
these libraries are already provided with the standard distribution of the 
following programming languages.

* GnuPlot 4.4.4

* GROMACS 4.5.5

* PERL 5 with the following libraries:
    * Bio::AlignIO
    * Bio::SeqIO
    * Carp
    * Cwd
    * Data::Dumper
    * DBI
    * File::Copy
    * File::Spec::Unix
    * Getopt::Long
    * Getopt::Std
    * IO::Socket::INET
    * LWP::UserAgent
    * Mail::IMAPClient
    * Math::Trig
    * Memory::Usage
    * MIME::Parser
    * Net::SMTP
    * Spreadsheet::Write
    * Statistics::Descriptive
    * Thread::Semaphore
    * XML::Simple

* PYTHON 2.7 with the following libraries:
    * biopython
    * gd

* R 3 with the following libraries:
    * cluster
    * clValid
    * RankAggreg
    * RColorBrewer
    * tcltk
    * tkrplot


--- INSTALLATION ---

Clone the RICEDDARIO package:

    $ git clone https://github.com/dcorrada/RICEDDARIO.git

Then, launch the installer script to update your bashrc file:

    $ cd RICEDDARIO;
    $ ./INSTALL.pl

