#!/bin/sh
log_file="/Users/USERNAME/Library/Logs/SBSVERSION/srvrpowerctrl.log"
now_time=`/bin/date`
/bin/echo "At $now_time, $0 is attempting to suspend the system.." >>$log_file
# hibernatemode 0 == suspend; hibernatemode 1 == hibernation; hibernatemode 3 == safe sleep, i.e sleep+hibernation
/usr/bin/pmset -a hibernatemode 0 >>$log_file
# Wait 3 seconds to let the setting settle..
/bin/sleep 3
# Sleep the system..
/sbin/shutdown -s now
