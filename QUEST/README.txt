## 1. SERVER STARTUP
The server script should be launched as super user:

    $ sudo su
    $ QUEST.server.pl

At first time you will be asked to edit the configuration file:

    QUEST server is not yet configured, do you want to proceed? [y/N] y

Just press `ENTER` for keeping the default values:

    host     [127.0.0.1]:
    maxsub   [1000]:
    port     [6090]: 
    threads  [8]: 

The _maxsub_ parameter define the maximum number of jobs that the server can handle (once you have submitted _maxsub_ jobs, the server should be restarted). The value of this parameter depends on how Perl has been compiled on your system. Optimal value for _threads_ parameter depends on your hardware performance, usually it should be setted with the amount of avalaible CPUs (or even 2x). Afterwards, the server is ready to accept the client requests:

    [2014/04/30 17:37:33] server initialized
    [2014/04/30 17:37:33] server is listening

Server can be stopped by press `CTRL+C`:

    [2014/04/30 17:56:08] QUEST server stopped

**WARNING:** it may happen that in the meanwhile some job is still running, in this case the server warns you about orphans:

    W- job [WH6OHKBF] was running while KILL signal arrived, check for accidental 
    orphans generated from 10252

    [2014/04/30 17:58:51] QUEST server stopped

The number refers to the PID of the parent process that it could be still alive.

### 1. 1. Launch the server as a daemon

You can launch the server at boot and redirect the standard output to a log file:

    $ sudo su
    $ touch /var/log/QUEST.server.log
    $ vim /etc/init.d/QUEST.server.sh

The file _/etc/init.d/QUEST.server.sh_ is a simple bash script like the following:

    #!/bin/sh
    
    export USER=root
    nice -n 19 /usr/local/RICEDDARIO/QUEST/QUEST.server.pl > /var/log/QUEST.server.log &
    
Finally register your script:

    $ cd /etc/init.d
    $ update-rc.d QUEST.server.sh defaults

## 2. SUBMITTING AND MANAGING JOBS
The client script should be launched as local user. In order to reproduce the subsequent example of commands make a copy of the _demo_ folder:

    $ cp -r /usr/local/PANDORA/QUEST/demo/ .
    $ cd demo

This folder contains three shell scripts. The file _ps.monitor.sh_ is a simple monitor for showing the processes which run during this sample session. The file _parent.sh_ is the script that we will submit, it launches in background another script (_child.sh_). To submit a job just simply type:

    $ QUEST.client.pl parent.sh
    
    >>> 00999 submissions to restart <<<
    
    [2014/04/30 18:38:31] job [3HRIT36O] queued,
    STDOUT/STDERR will be written to </home/dario/tmp/demo/QUEST.job.3HRIT36O.log>

The header string `>>> 00999 submissions to restart <<<` indicates how many jobs remain to be submitted before the server shoul be restarted. As well the server returns to the client a message specifying the job identifier (jobID) and a log file that will be created to capture all the stuff coming from the script. When the job is terminated the log file will contains something like the following:

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

The trailing lines below `*** QUEST SUMMARY ***` show the summaries about your submitted job. 

By default the client assign one thread per script. If you forecast to use more than a single thread you can specify it using the `-n` option:

    $ QUEST.client.pl -n 5 parent.sh

**WARNING:** the characters like `;` or `|` are used by internal commands of the server, you must avoid to use these for the name of your script files.

If the number of threads required per job exceeds the amount of avalaible threads an error message will be returned:

    E- Number of threads required (5) is higher than allowed (4)
            at /usr/local/PANDORA/QUEST/QUEST.client.pl line 110

Now shall we try to submit more than one job. For the sake of simplicity, in this example we submit the same script multiple times (as if we want to get several different jobs):

    $ QUEST.client.pl -n 4 parent.sh
    [...]
    $ QUEST.client.pl -n 2 parent.sh
    [...]
    $ QUEST.client.pl -n 3 parent.sh

Unlike the previous example, each of the three jobs herein submitted does not exceed the amount of avalaible threads. However, the sum of the required threads (9) exceeds it. Therefore, some of these job will automatically queued until running jobs release a sufficient number of threads. The option `-l` allows you 
to check the jobs list and their respective status:

    $ QUEST.client.pl -l

    Avalaible threads 0 of 4

    --- JOB RUNNING ---
    [2014/04/30 21:53:26]     dario  4  7578G9E6  [PID: 10252]  </home/dario/tmp/demo/parent.sh>

    --- JOB QUEUED ---
    [2014/04/30 21:53:31]     dario  2  KFB3FM99  </home/dario/tmp/demo/parent.sh>
    [2014/04/30 21:53:37]     dario  3  21WM0G8G  </home/dario/tmp/demo/parent.sh>

When jobs are running the PID of the main process i returned. From the jobs list we can also view the list of jobIDs, so you can kill your running/queued jobs every time:

    $ QUEST.client.pl -k

    job [KFB3FM99] has been killed


### 2. 1. Server logs

If you switch to the terminal in which the server has been launched realtime log messages are printed in order to track the activities of the client:

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

### 2. 2. Managing jobs that come from Schrodinger Suite

Since the Schrodinger Suite jobs are already scheduled by an internal job manager, scripts that call them should be treated carefully. In first instance, the _.sh_ files need to have specific lines, like the following example:

    #!/bin/sh

    # export the environment vars
    export SCHRODINGER=/usr/local/schrodinger_2012
    export LM_LICENSE_FILE=62158@192.168.1.4

    # launch the job
    $SCHRODINGER/macromodel minijob


In this script you need to export the environment variables of the Schrodinger software and related license manager host.

**WARNING:** do not launch more than a single Schrodinger job per _.sh_ script file.

Finally, the option `-s` must be spcified during the job submission:

    $ QUEST.client.pl -s erwin.sh

If you take a look to the joblist you will something like this:

    $ QUEST.client.pl -l
    
    Avalaible threads 0 of 4
    
    --- JOB RUNNING ---
    [2014/05/07 15:21:53]     dario  2  76PJL237  [PID: 11382]  </home/dario/tmp/schro/parent.sh> null
    [2014/05/07 15:22:19]     dario  1  UE2YWZ2J  [Schrodinger lbpc7-0-536a338b]  </home/dario/tmp/schro/erwin.sh>
    
    --- JOB QUEUED ---
    [2014/05/07 15:22:03]     dario  3  R9B7KW99  </home/dario/tmp/schro/child.sh>
    [2014/05/07 15:22:28]     dario  4  LVSTVZL2  </home/dario/tmp/schro/erwin2.sh>
    
For Schrodinger running jobs the PID flag is substituted by `[Schrodinger lbpc7-0-536a338b]`, where the JobId of the internal Schrodinger job manager is returned. When you try to kill one of these jobs you will receive a warning like this:

    $ QUEST.client.pl -k UE2YWZ2J
    
    [...]
    
    server is killing...
    killing the Schrodinger's cat is unsafe, try to use the following commad:

        $ $SCHRODINGER/jobcontrol -kill lbpc7-0-536a338b
    
You are encouraged to kill Schrodinger jobs from the _jobcontrol_ tool when they are already started (ie _running_). Those jobs still _queued_ can be killed as usual by the `-k` option.

### 2. 3. Batch submission

The QUEST server does not handle more than a thousand of submitted jobs (such limit an be configured in the _QUEST.conf_ file). With the release 14.5.c a warning message will be sent to the client if the quota has been exceeded:

    WARNING: the server has collected 1000 jobs. You should restart the 
    server before submitting another job.

Moreover, if you plan to use a bot for multiple submission, you must keep in mind to insert a delay between the QUEST client calls (e.g.: add a "sleep" of 1sec before):

    #!/usr/bin/perl
    
    opendir DH, '/home/dario/tmp';
    my @scripts = grep { /myscript.\d+.sh/ } readdir(DH);
    closedir DH;
    
    foreach my $script (@scripts) {
        sleep 1;
        my $log = qx/clear; \/usr\/local\/QUEST\/QUEST.client.pl $script/;
        print "$log\n";
    }
    
    exit;
