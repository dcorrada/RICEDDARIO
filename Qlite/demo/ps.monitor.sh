#!/bin/sh

while :
do
    clear;
    echo "Press [CTRL+C] to stop..";
    echo "";
    ps aux | grep -P "QUEST|parent\.sh|child\.sh|sleep" | cut -c1-120;
    sleep 2;
done