#!/bin/sh
old=$(ls -rt /var/log/wtmp* |head -1)
#echo "oldest file: $old"
user=$(last -F -f "$old" |tac |head -4 |egrep -v "addm_gt|reboot|wtmp" |awk '{print $1}')
echo $user
