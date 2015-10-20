#!/bin/sh
log_file="/Users/USERNAME/Library/Logs/SBSVERSION/srvrpowerctrl.log"
now_time=`/bin/date`
wake_time="$1 $2"
/bin/echo "At $now_time, $0 scheduled system wakeup time for $wake_time " >>$log_file
/usr/bin/pmset schedule wake "$wake_time" >>$log_file
