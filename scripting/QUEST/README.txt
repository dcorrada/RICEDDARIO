********************************************************************************
QUEST - QUEue your ScripT
release 14.4

Copyright (c) 2011-2014, Dario CORRADA <dario.corrada@gmail.com>

This work is licensed under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported License.
********************************************************************************

QUEST is a client/server application for handling the batch submission of 
several executable files (ie jobs) over a single machine.


*** SERVER ***
The server script can be launched either as super user or local user. If the 
server is launched as local user only that local user can submit the jobs from 
the client script. Otherwise, if the server is launched as super user, all the 
local users can submit their jobs.

-- CONFIGURATION FILE
The configuration file is defined as '/etc/QUEST.conf', it will be generated at 
the first start of the server. The parameters you will asked to configure are 
the following:

    host        the IP address of the local host (usually 127.0.0.1)
    
    port        the port by which client and server communicate
    
    protocol    the communication protocol
    
    reuse       opened sockets will be reused
    
    sockets     how many sockets to open
    
    threads     how many threads will be managed by the server (usually the 
                number of avalaible processors)


*** CLIENT ***
The client script allows you to submit a job or show the list of jobs already 
submitted.

-- SUBMITTING YOUR JOBS
First check that the file you want to submit as a job is executable. The 
characters like ';' or '|' are used by internal commands of the server, you must 
avoid to use these for the name of your file. Then, move to your working 
directory and submit your job:

    foo$ cd workdir
    foo$ QUEST.client.pl -n 5 myscript.sh

The execution of file 'myscript.sh' has been submitted, and you have reserved 
for your job 5 threads (-n option, default is 1). A log file of the standard 
output will be written in your working directory once your job terminates.

-- MONITORING YOUR JOBS
In order to show the job list handled by the server:

    foo$ QUEST.client.pl -l

You will obtain an output such this one:

    --- JOB RUNNING ---
    [2014/04/25 12:42:55]       bar  4  I4O1ES06  </home/bar/minescript.sh>
    --- JOB QUEUED ---
    [2014/04/26 17:29:33]       foo  5  K8S9RHRF  </home/foo/myscript.sh>

In this example your job has been queued, since another user has already taken 4 
threads and, by now, no sufficient threads are avalaible to run your job. When 
the job of user 'bar' will be finished, 4 threads will be released and your job 
will start. The job lines show, respectively: the date when the job has been 
queued/started; the user name; the number of threads required for the job; the 
job ID assigned by the server; the executable file coupled with the job.

-- KILLING YOUR JOBS
The QUEST server tracks your jobs but not the child processes which can start 
from your coupled executable files. Therefore, if you want to kill a job 
erroneously submitted, you should kill your executable (using bash commands like 
top). Afterwards, the server will see your job as accomplished.
