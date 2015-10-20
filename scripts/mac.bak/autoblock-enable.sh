#!/bin/sh
# Setup script for automatic SrvrPowerCtrl setblock on login, automatic clearblock on logout

setup_dir=`dirname $0`
user=`/usr/bin/whoami`
scuser=`/usr/bin/logname`
user_dir="/Users/$scuser"

echo "Enabling auto SrvrPowerCtrl setblock on login, clearblock on logout -- for user $scuser"

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

cd "$setup_dir"

#copy the scripts to the user dir
cp ./spc-setblock.sh "$user_dir/login.sh"
cp ./spc-clearblock.sh "$user_dir/logout.sh"

chmod 750 "$user_dir/login.sh"
chmod 750 "$user_dir/logout.sh"

# endable login & logout hooks
/usr/bin/defaults write com.apple.loginwindow LoginHook "$user_dir/login.sh"
/usr/bin/defaults write com.apple.loginwindow LogoutHook "$user_dir/logout.sh"

echo "Done! Auto-block is now enabled for user $scuser"

