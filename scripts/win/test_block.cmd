@echo off
set SBSIP=127.0.0.1
set CLIPORT=9090

rem block SrvrPowerCtrl actions..

scclitool.exe srvrpowerctrl setblock Setting_block_message viacli -h %SBSIP% -p %CLIPORT%

