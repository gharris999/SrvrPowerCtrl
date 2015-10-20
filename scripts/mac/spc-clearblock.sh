#!/bin/sh
/usr/bin/logger -i "logouthook"
SCIp='127.0.0.1'
CLIPort='9090'

echo srvrpowerctrl clearblock Logoff_clearing_block viacli | nc -w 3 $SCIp $CLIPort
exit 0
