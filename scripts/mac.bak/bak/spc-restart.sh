#!/bin/sh
log_file="/Users/USERNAME/Library/Logs/SBSVERSION/srvrpowerctrl.log"
now_time=`/bin/date`
/bin/echo "At $now_time, $0 is attempting to restart SBSVERSION.." >>$log_file
/sbin/SystemStarter stop SBSVERSION
/bin/sleep 10
/sbin/SystemStarter start SBSVERSION
