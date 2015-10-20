#!/bin/sh
#
# SrvrPowerCtrl plugin test helper script for linux, adapted from a script by Epoch1970..
#
#

user=`whoami`
if [ "$user" = "root" ]
  then
  /usr/bin/wall <<MSG0;
  ERROR: This script must NOT be run with root credentials, either via:
  # sudo $0
  or under su.

  Instead, please run this script as a regular user:
  # $0

MSG0
  exit -1
fi



HOST=`hostname -s`
#SBSUSER=`/usr/bin/logname`
SBSUSER=`whoami`


log_file=/Users/USERNAME/Library/Logs/SBSVERSION/srvrpowerctrl.log

echo "$0 $1" >>$log_file

/usr/bin/wall <<MSG1;

  ****************************************************************************
  *****************            THIS IS A TEST               ******************
  ****************************************************************************

  This is a SrvrPowerCtrl test of user ${SBSUSER}'s ability to
  execute scripts on $HOST.

  You may now see a message announcing immediate shutdown of this
  system.  $HOST WILL NOT really shutdown.

  ****************************************************************************
  *****************          THIS IS ONLY A TEST            ******************
  ****************************************************************************
MSG1

sudo -K
sleep 5;

sudo /sbin/shutdown -k now '(NOT! Just kidding, folks.)' >/dev/null 2>&1 && OK=1 || OK=0;

if [ "$OK" -eq 1 ]; then
  /usr/bin/wall <<MSG2;

  ****************************************************************************
  *****************       SUCCESS! SUCCESS! SUCCESS!        ******************
  ****************************************************************************

  Success! User $SBSUSER has passwordless permission to
  shutdown $HOST.

  This test script, in voluntary cooperation with your operating system, has
  has been developed to inform you of permissions problems.  Had this been
  an actual shutdown event, your system would have halted by now and you
  wouldn't be reading this.

  This concludes this test of ${SBSUSER}'s ability to run privileged
  commands on $HOST.

MSG2
  echo "Success! User $SBSUSER has passwordless permission to shutdown $HOST." >>$log_file
  sleep 5
  exit 0
else
  echo -e "\n";
  /usr/bin/wall <<MSG3;

  ****************************************************************************
  *****************          ERROR! ERROR! ERROR!           ******************
  ****************************************************************************

  Failure! There are permissions problems for user $SBSUSER.

  Further modificatons need to be made to the /etc/sudoers file to give
  $SBSUSER the correct passwordless permissions to run privileged
  commands on $HOST.

  Try re-running the srvrpowerctrl-setup.sh script again and consult the
  documentation.

MSG3
  echo "Failure! There are permissions problems for user $SBSUSER." >>$log_file
  sleep 5
  exit -1
MSG3
fi

