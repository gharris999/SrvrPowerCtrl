#!/bin/sh
#
# SrvrPowerCtrl plugin test helper script for linux, adapted from a script by Epoch1970..
#
#

load_helper_file(){

	FUNCFILE='spc-functions.sh'

	HELPERFILE="$(dirname $(readlink -f $0 2>/dev/null) 2>/dev/null)/${FUNCFILE}"

	if [ ! -f "$HELPERFILE" ]; then
		HELPERFILE="${0%$(basename $0)*}/${FUNCFILE}"
	fi

	if [ -f "$HELPERFILE" ]; then
		. $HELPERFILE
	else
		echo "Error: could not find ${HELPERFILE}."
	fi

}

load_helper_file

HOST=$(hostname -s)
SBSUSER=$(whoami)
SHUTDOWNOK=1

####################################################################################
# Check to see that we're not root..
#
check_not_root(){
	if [ $(whoami) = "root" ]; then
		/usr/bin/wall <<MSG0;
  ERROR: This script must NOT be run with root credentials, either via:

  # sudo $0

  or under su.  Instead, please run this script as a regular user via:

  # sudo -u username $0

  or directly executed by a regular user account.

MSG0
		exit 1
	fi
}

####################################################################################
# Initital wall message
#
initial_banner(){
	spc_log_message "${DATE} ${SCRIPT} for user ${SBSUSER}"
	/usr/bin/wall <<MSG;

  ****************************************************************************
  *****************            THIS IS A TEST               ******************
  ****************************************************************************

  This is a SrvrPowerCtrl test of user ${SBSUSER}'s ability to
  passwordlessly execute power management commands on ${HOST}.

  You may now see a message announcing immediate shutdown of this
  system.  ${HOST} WILL NOT really shutdown.

  ****************************************************************************
  *****************          THIS IS ONLY A TEST            ******************
  ****************************************************************************

MSG

	sleep 5;
}

####################################################################################
# Run a fake shutdown test
#
test_fake_shutdown(){
	sudo -K

	echo "" | sudo -S /sbin/shutdown -h -k now 'NOT! Just kidding, folks.' >/dev/null 2>&1 && SHUTDOWNOK=1 || SHUTDOWNOK=0;

	sleep 5;
}

####################################################################################
# Report success
#
success_banner(){
	wall <<MSG;

  ****************************************************************************
  *****************       SUCCESS! SUCCESS! SUCCESS!        ******************
  ****************************************************************************

  Success! User ${SBSUSER} has passwordless permission to
  shutdown ${HOST}.

  This test script, in voluntary cooperation with your operating system, has
  has been developed to inform you of permissions problems.  Had this been
  an actual shutdown event, your system would have halted by now and you
  wouldn't be reading this.

  This concludes this test of ${SBSUSER}'s ability to run power
  management commands on ${HOST}.

MSG
	spc_log_message "Success! User ${SBSUSER} has passwordless permission to shutdown ${HOST}."
	sleep 5
	exit 0
}

####################################################################################
# Report failure
#
failure_banner(){
	#echo  ' '
	/usr/bin/wall <<MSG;

  ****************************************************************************
  *****************          ERROR! ERROR! ERROR!           ******************
  ****************************************************************************

  Failure! There are permissions problems for user ${SBSUSER}.

  Further modificatons need to be made to the /etc/sudoers file to give
  ${SBSUSER} the correct passwordless permissions to run power
  management commands on ${HOST}.

  Try re-running the srvrpowerctrl-setup.sh script again and consult the
  documentation.

MSG
	spc_log_message "Failure! There are permissions problems for user ${SBSUSER}."
	sleep 5
	exit -1
}


####################################################################################
# main()
#
for ARG in $*
do
case $ARG in
	--help)
		echo "${SCRIPT} [--log]"
		exit 0
		;;
	--log)
		LOGGING=1
		;;
esac
done

check_not_root
initial_banner
test_fake_shutdown

if [ $SHUTDOWNOK -eq 1 ]; then
	success_banner
else
	failure_banner
fi
