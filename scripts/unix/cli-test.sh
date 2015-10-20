#!/bin/sh

# Test script demonstrating SrvrPowerCtrl CLI functions via netcat..

# Get the next wake alarm from SrvrPowerCtrl

RTCALARM=$(printf "srvrpowerctrl getwakealarm\nexit\n" | nc -w1 127.0.0.1 9090 | sed -n -e 's/^.*%3A\([[:digit:]]*\).*$/\1/p')

