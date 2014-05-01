********************************************************************************
QUEST - QUEue your ScripT
release 14.4.a

Copyright (c) 2011-2014, Dario CORRADA <dario.corrada@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

QUEST is a client/server application for handling the batch submission of 
several executable files (ie jobs) over a single machine.


1. SERVER STARTUP

The server script should be launched as super user:

    $ sudo su
    $ QUEST.server.pl

At first time you will be asked to edit the configuration file:

    QUEST server is not yet configured, do you want to proceed? [y/N] y

Just press ENTER for keeping the default values:

        host     [127.0.0.1]: 
        port     [6090]: 
        threads  [8]: 

Optimal value for "threads" parameter depends on your hardware performance, 
usually it should be setted with the amount of avalaible CPUs (or even 2x). 
Afterwards, the server is ready to accept the client requests:

    [2014/04/30 17:37:33] server initialized
    [2014/04/30 17:37:33] server is listening

Server can be stopped by press CTRL+C:

    [2014/04/30 17:56:08] QUEST server stopped

WARNING: it may happen that in the meanwhile some job is still running, in this 
case the server warns you about orphans:

    W- job [WH6OHKBF] was running while KILL signal arrived, check for accidental 
    orphans generated from </home/dario/tmp/demo/parent.sh>

    [2014/04/30 17:58:51] QUEST server stopped


2. SUBMITTING AND MANAGING JOBS

The client script should be launched as local user. In order to reproduce the 
subsequent example of commands make a copy of the demo folder:

    $ cp -r /usr/local/PANDORA/QUEST/demo/ .
    $ cd demo

This folder contains three shell scripts. The file "ps.monitor.sh" is a simple 
monitor for showing the processes which run during this sample session. The file 
"parent.sh" is the script that we will submit, it launches in background another 
script ("child.sh"). To submit a job just simply type:

    $ QUEST.client.pl parent.sh

    [2014/04/30 18:38:31] job [3HRIT36O] queued,
    STDOUT/STDERR will be written to </home/dario/tmp/demo/QUEST.job.3HRIT36O.log>

As well the server returns to the client a message specifying the job identifier 
(jobID) and a log file that will be created to capture all the stuff coming from 
the script. When the job is terminated the log file will contains something like 
the following:

    singing a lullaby for my child
    child goes to sleep...
    parent goes to sleep...
    child awake
    parent awake
    *** QUEST SUMMARY ***
    EXECUTABLE.....: /home/dario/tmp/demo/parent.sh
    WORKING DIR....: /home/dario/tmp/demo
    THREADS USED...: 1
    QUEUED TIME....: 00:00:00
    RUNNING TIME...: 00:16:40

The trailing lines below "*** QUEST SUMMARY ***" show the summaries about your 
submitted job. 

By default the client assign one thread per script. If you forecast to use more 
than a single thread you can specify it using the '-n' option:

    $ QUEST.client.pl -n 5 parent.sh

WARNING: the characters like ';' or '|' are used by internal commands of the 
server, you must avoid to use these for the name of your script files.

If the number of threads required per job exceeds the amount of avalaible 
threads an error message will be returned:

    E- Number of threads required (5) is higher than allowed (4)
            at /usr/local/PANDORA/QUEST/QUEST.client.pl line 110

Now shall we try to submit more than one job. For the sake of simplicity, in 
this example we submit the same script multiple times (as if we want to get 
several different jobs):

    $ QUEST.client.pl -n 4 parent.sh
    [...]
    $ QUEST.client.pl -n 2 parent.sh
    [...]
    $ QUEST.client.pl -n 3 parent.sh

Unlike the previous example, each of the three jobs herein submitted does not 
exceed the amount of avalaible threads. However, the sum of the required threads 
(9) exceeds it. Therefore, some of these job will automatically queued until 
running jobs release a sufficient number of threads. The option '-l' allows you 
to check the jobs list and their respective status:

    $ QUEST.client.pl -l

    Avalaible threads 0 of 4

    --- JOB RUNNING ---
    [2014/04/30 21:53:26]     dario  4  7578G9E6  </home/dario/tmp/demo/parent.sh>

    --- JOB QUEUED ---
    [2014/04/30 21:53:31]     dario  2  KFB3FM99  </home/dario/tmp/demo/parent.sh>
    [2014/04/30 21:53:37]     dario  3  21WM0G8G  </home/dario/tmp/demo/parent.sh>

From the jobs list we can also view the list of jobIDs, so you can kill your 
running/queued jobs every time:

    $ QUEST.client.pl -k

    server is killing.....
    job [KFB3FM99] has been killed


3. SERVER LOGS

If you switch to the terminal in which the server has been launched realtime log 
messages are printed in order to track the activities of the client:

    [2014/04/30 22:16:08] server initialized
    [2014/04/30 22:16:08] server is listening
    [2014/04/30 22:16:23] job [X8Q8B839] submitted by [dario]
    [2014/04/30 22:16:34] killing job [X8Q8B839] requested by [dario]
            killing child pid 17265...
            killing child pid 17264...
            killing child pid 17263...
            killing child pid 17262...
            killing child pid 17261...
            killing child pid 17257...
    ^C
    
    [2014/04/30 22:17:12] QUEST server stopped

