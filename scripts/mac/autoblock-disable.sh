#!/bin/sh
# Setup script for automatic SrvrPowerCtrl setblock on login, automatic clearblock on logout

setup_dir=`dirname $0`
user=`/usr/bin/whoami`
scuser=`/usr/bin/logname`
user_dir="/Users/$scuser"

echo "Disabling auto SrvrPowerCtrl setblock on login, clearblock on logout -- for user $scuser"

if [ "$user" != "root" ]
  then
    echo 'ERROR: this script must be run under root credentials via:'
    echo "# sudo $0"
    exit -1
fi

if [ "$scuser" == "$user" ]
  then
    echo 'ERROR: this script must be run under root credentials, but'
    echo 'not AS root.  Use:'
    echo "# sudo $0"
    exit -1
fi

# disable login & logout hooks
/usr/bin/defaults delete com.apple.loginwindow LoginHook
/usr/bin/defaults delete com.apple.loginwindow LogoutHook

mv "$user_dir/login.sh" "$user_dir/login.sh.not"
mv "$user_dir/logout.sh" "$user_dir/logout.sh.not"

echo "Done! Auto-block is now disabled for user $scuser"



