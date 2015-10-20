#!/bin/sh
#
# SrvrPowerCtrl plugin test helper script for linux, adapted from a script by Epoch1970..
#
#

myrealpath(){
	echo "$(perl -e 'use Cwd "abs_path";print abs_path(shift)' $0)"
}


load_helper_file(){

	FUNCFILE='spc-functions.sh'

	HELPERFILE="$(dirname $(myrealpath $0))/${FUNCFILE}"

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
RETVAL=0

####################################################################################
# Check to see that we're not root..
#
check_not_root(){
	if [ $(whoami) = "root" ]; then
		wall <<MSG0;
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
# Warn if not running under the SBS/LMS account..
#
check_sbs_user(){
	RETVAL=1
	if [ -z "$SLIMUSERNAME" ]; then
		spc_get_slim_username
		RETVAL=$?
	fi
	
	# If we REALLY know the LMS/SBS user account and we're not it...
	if ( [ $RETVAL -ne 0 ] && [ ! "$SBSUSER" = "$SLIMUSERNAME" ] ); then
		wall <<MSG0;
  ****************************************************************************
  **********************   WARNING * WARNING * WARNING  **********************
  ****************************************************************************

  WARNING: You are running this script for the '${SBSUSER}' account but I detect
  that the SBS/LMS user is actually '${SLIMUSERNAME}'.  You really ought
  to run this script via:

  # sudo -u ${SLIMUSERNAME} $0

  We'll allow this test to proceed, but please be aware that these are not
  the droids you're interested in.
  
MSG0
		sleep 5
		return 1
	fi
	return 0
}

####################################################################################
# Run a fake shutdown test
#
test_fake_shutdown(){
	sudo -K

	# On OS X, the SBS user is likely to have a password...so we can't feed sudo a blank password via echo "" | sudo -S
	sudo -n shutdown -k now '(NOT! Just kidding, folks.)' >/dev/null 2>&1 && SHUTDOWNOK=1 || SHUTDOWNOK=0;

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
	RETVAL=0
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
	RETVAL=-1
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
	--serverlog)
		LOGGING=1
		SERVERLOGGING=1
		;;
esac
done

check_not_root
initial_banner
check_sbs_user
test_fake_shutdown

if [ $SHUTDOWNOK -eq 1 ]; then
	success_banner
else
	failure_banner
fi

exit $RETVAL