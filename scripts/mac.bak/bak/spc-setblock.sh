#!/bin/sh
/usr/bin/logger -i "LoginHook"
SCIp='127.0.0.1'
CLIPort='9090'

echo srvrpowerctrl setblock Logon_block viacli | nc -w 3 $SCIp $CLIPort
exit 0
