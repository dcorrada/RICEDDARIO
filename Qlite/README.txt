# QUEST - QUEue your ScripT
_The following example of commands are based on script file deposited in the `Qlite/test` folder._

## 1. REQUIREMENTS
The Perl DBI module and the SQLite3 driver need to be installed. To install the `DBI` module:

    $ wget http://bo.mirror.garr.it/mirrors/CPAN/authors/id/T/TI/TIMB/DBI-1.631.tar.gz
    $ tar xvfz DBI-1.631.tar.gz
    $ cd DBI-1.631
    $ perl Makefile.PL
    $ make
    $ make install

To install the SQLite driver `DBD::SQLite`:

    $ wget http://bo.mirror.garr.it/mirrors/CPAN/authors/id/I/IS/ISHIGAKI/DBD-SQLite-1.42.tar.gz
    $ tar xvfz DBD-SQLite-1.42.tar.gz
    $ cd DBD-SQLite-1.42
    $ perl Makefile.PL
    $ make
    $ make install

## 2. SERVER STARTUP
The server script must be launched as super user:

    $ sudo su
    $ QUEST.server.pl

At first time you will be asked to edit the configuration file:

    QUEST server is not yet configured, do you want to proceed? [y/N] y

Just press `ENTER` for keeping the default values:

    host     [127.0.0.1]:
    port     [6090]: 
    threads  [8]: 

Optimal value for `threads` parameter depends on your hardware performance. Usually it should be setted with the amount of avalaible CPUs (or even 2x).

Afterwards, the server is ready to accept the client requests:

    CONFIGS...: /etc/QUEST.conf
    DATABASE..: /etc/QUEST.db

    [2014/06/16 10:55:02] server initialized
    [2014/06/16 10:55:02] server is listening

Server can be stopped by press `CTRL+C`:

    [2014/06/16 10:58:41] QUEST server stopped


## 3. SUBMITTING JOBS
The client script should be launched as local user. To submit a job just simply type:

    $ QUEST.client.pl sleeper.sh

The client will return a message in which a jobid has been assigned to your script and your job has been submitted to the server:

    assigning jobid...
    [2014/06/16 11:06:13] job [727261C0] submitted

When your job effectively starts a log file (e.g. `QUEST.job.727261C0.log`) will be generated in your working directory. The log file will store all the STDERR/STDOUT flow generated from your script.

### 3. 1. Define the number of threads
By default the client assign one thread per script. If you forecast to use more than a single thread you can specify it using the `-n` option:

    $ QUEST.client.pl -n 5 sleeper.sh

### 3. 2. Define the type of queue
QUEST handles two types of queue, `slow` and `fast`. By default the jobs will be submitted in the _slow_ queue. Otherwise you can set it manually with the `-q` option:

    $ QUEST.client.pl -q fast sleeper.sh

The order by which a job exits the queue list and starts is defined at three hierarchical levels:

1. the jobs that require a lesser number of threads are privileged;

2. the jobs that are queued as _fast_ have priority over the ones tagged as _slow_;

3. the job that are queued for longer time are privileged.

### 3. 3. Submitting jobs that come from Schrodinger Suite
Since the Schrodinger Suite jobs are already scheduled by an internal job manager, scripts that call them should be treated carefully. In first instance, the script file needs to have specific lines, like the following example:

    #!/bin/sh

    # export the environment vars
    export SCHRODINGER=/usr/local/schrodinger_2012
    export LM_LICENSE_FILE=62158@192.168.1.4

    # launch the job
    $SCHRODINGER/prime_mmgbsa mmgbsa.00001.maegz

In this script you need to export the environment variables of the Schrodinger software and related license manager host.

**WARNING:** do not launch more than a single Schrodinger job per script file.

Finally, the option `-s` must be specified during the job submission:

    $ QUEST.client.pl -s mmgbsa.00001.sh

**NOTE:** the option `-s` is deprecated, where possible Schrodinger jobs sould be run with `NOJOBID` flag. The following script does not need the use of `-s` option:

    #!/bin/sh

    # export the environment vars
    export SCHRODINGER=/usr/local/schrodinger_2012
    export LM_LICENSE_FILE=62158@192.168.1.4

    # launch the job
    $SCHRODINGER/prime_mmgbsa mmgbsa.00001.maegz -NOJOBID

## 4. MANAGING YOUR JOBS
You can monitor the status of the server every time with the following command:

    $ QUEST.client.pl -l

The client will return a brief summary status:

    Avalaible threads 0 of 4
    
    --- JOB RUNNING ---
    [0Y01628R]  dario  3  slow  </home/dario/tmp/Qlite/mmgbsa.00002.sh>
    [9W70KP6N]  dario  1  slow  </home/dario/tmp/Qlite/mmgbsa.00001.sh>
    
    --- JOB QUEUED ---
    [I1OE56N2]  dario  1  fast  </home/dario/tmp/Qlite/sleeper.sh>
    [6O9F8LOF]  dario  2  slow  </home/dario/tmp/Qlite/mmgbsa.00004.sh>

The columns describe the repective fields:

    [jobid]  user  threads  queue  <script file>

You can also view the details of a specific job with `-d` option:

    $ QUEST.client.pl -d 0Y01628R

obtaining this

    *** JOB 0Y01628R ***
    STATUS........: running
    USER..........: dario
    THREADS.......: 3
    QUEUE.........: slow
    SCHRODINGER...: lbpc7-1-539ebcb7
    SCRIPT........: /home/dario/tmp/Qlite/mmgbsa.00002.sh
    SUBMITTED.....: [2014/06/16 11:29:45]
    STARTED.......: [2014/06/16 11:29:45]
    FINISHED......: null

### 4. 1. Killing your jobs
You can kill your running/queued jobs every time with `-k` option:

    $ QUEST.client.pl -k 0Y01628R

**NOTE:** killing Schrodinger jobs (ie those shell scripts launched with `-s` option) is not managed by QUEST. As a result the following message will be displayed:

    REJECTED: try to use the following commad

        $ $SCHRODINGER/jobcontrol -kill lbpc7-1-539ebcb7