#!/bin/sh
#!/bin/sh
#
# SrvrPowerCtrl plugin helper script for OS X.
#
# This script will set a system wakeup event using pmset.
#
# Call this script from SrvrPowerCtrl with "sudo /usr/local/sbin/spc-sleep.sh %d".
#

myrealpath(){
	local ABSPATH=`perl -e 'use Cwd "abs_path";print abs_path(shift)' "$1"`
	echo "$ABSPATH"
}

load_helper_file(){

	local SOURCEDIR=`myrealpath "$0"`
	SOURCEDIR=`dirname "$SOURCEDIR"`

	helper_functions="${SOURCEDIR}/spc-functions.sh"

	if [ ! -f "$helper_functions" ]; then
		echo "ERROR: Cannot find ${helper_functions}"
		exit 1
	fi

	. "$helper_functions"

}

load_helper_file

VERBOSE=1

# Default sleep mode is S3
SLEEPMODE=0

# Disable Wake for network access (enable just before sleep to enable WOL, otherwise, disable)
DISABLEWONA=1

# Enable Wake on magic packet
ENABLEWOMP=1

JUST_SHOW=0

# Labesl for hibernation modes supported by pmset..
aMODE[0]='sleep'
aMODE[1]='old-hibernation'
aMODE[3]='safe-sleep'
aMODE[25]='suspend/hibernation'

show_current_mode(){
	# get the current mode
	local CURRENTMODE=$(pmset -g | grep 'hibernatemode' | sed -e 's/^[^[:digit:]]*\([[:digit:]]*\)[^[:digit:]]*$/\1/')
	spc_disp_message "System is currently configured for ${aMODE[$CURRENTMODE]}."

	local CURRENTWONA=$(systemsetup -getwakeonnetworkaccess)
	if [ ! -z "$CURRENTWONA" ]; then
		local CURRENTWONA_ISOFF=$(echo "$CURRENTWONA" | egrep 'Off' | wc -l)
		if [ $CURRENTWONA_ISOFF -gt 0 ]; then
			spc_disp_message "Wake on network access is OFF."
		else
			spc_disp_message "Wake on network access is ON."
		fi
	fi

		# Make sure that WOMP is DISABLED.
	local CURRENTWOMP=$(pmset -g | grep 'womp' | sed -e 's/^[^[:digit:]]*\([[:digit:]]*\)[^[:digit:]]*$/\1/')
	if ([ ! -z "$CURRENTWOMP" ] && [ $CURRENTWOMP -gt 0 ]); then
		pmset -a womp 0
	fi



}

system_sleep(){
	HIBERNATEMODE="$1"
	local RETVAL
	local CURRENTWOMP=
	local CURRENTWONA=
	local CURRENTWONA_ISOFF=

	# Default to sleep
	if [ -z "$HIBERNATEMODE" ]; then
		HIBERNATEMODE=0
	fi

	# Set WOMP -- wake on magic packet..
	CURRENTWOMP=$(pmset -g | grep 'womp' | sed -e 's/^[^[:digit:]]*\([[:digit:]]*\)[^[:digit:]]*$/\1/')
	if ([ ! -z "$CURRENTWOMP" ] && [ $CURRENTWOMP -eq 0 ] && [ $ENABLEWOMP -gt 0 ]); then
		spc_disp_message "Enabling WOMP.."
		pmset -a womp 1
	elif ([ ! -z "$CURRENTWOMP" ] && [ $CURRENTWOMP -gt 0 ] && [ $ENABLEWOMP -lt 1 ]); then
		spc_disp_message "Disabling WOMP.."
		pmset -a womp 0
	fi

	## Disable networkoversleep
	#CURRENTNOS=$(pmset -g | grep 'networkoversleep' | sed -e 's/^[^[:digit:]]*\([[:digit:]]*\)[^[:digit:]]*$/\1/')
	#if ([ ! -z "$CURRENTNOS" ] && [ $CURRENTNOS -gt 1 ]); then
	#	pmset -a networkoversleep 0
	#fi


	# From man pmset:
	#
	# We do not recommend modifying hibernation settings. Any changes you make are not
	# supported. If you choose to do so anyway, we recommend using one of these three
	# settings. For your sake and mine, please don't use anything other 0, 3, or 25.

	# hibernatemode 0 == sleep, 								ie 0b0000 0000
	# hibernatemode 3 == safe sleep, i.e sleep+hibernation,		ie 0b0000 0011
	# hibernatemode 25 == hibernation (called 'suspend'),		ie 0b0001 0001

	# See also:
	# http://www.tuaw.com/2011/08/22/why-hibernate-or-safe-sleep-mode-is-no-longer-necessary-in-os/
	# http://developer.apple.com/library/mac/#documentation/Darwin/Reference/ManPages/man1/pmset.1.html
	#
	# OS X version variations:
	# 10.4.1 (intel Tiger) no mention of hibernatemode
	# 10.5 (Leopard) only mentions bits 0 & 1,
	# 10.6 (Snow Leopard) bits 0,1,3,4
	# 10.7.4 (Lion) bits 0,1,3,4

	# get the current mode
	CURHIBERNATEMODE=$(pmset -g | grep 'hibernatemode' | sed -e 's/^[^[:digit:]]*\([[:digit:]]*\)[^[:digit:]]*$/\1/')

	# Older versions of OS X (Jaguar, Panther, Tiger) won't have a 'hibernatemode' setting, so
	# don't even try to change the mode..
	if ([ ! -z "$CURHIBERNATEMODE" ] && [ $CURHIBERNATEMODE -ne $HIBERNATEMODE ]); then
		spc_disp_message "Changing the system hibernatemode to ${aMODE[$HIBERNATEMODE]}."
		pmset -a hibernatemode $HIBERNATEMODE
		if [ $? -eq 0 ]; then
			CURHIBERNATEMODE=$HIBERNATEMODE
		fi
		# Wait 3 seconds to let the setting settle..
		sleep 3
	fi

	# Sleep the system..
	local NOWTIME=$(date)
	spc_disp_message "Putting the system into ${aMODE[$CURRENTMODE]} mode at ${NOWTIME}."

	# See: http://hints.macworld.com/article.php?story=20100401103451497

	#CURRENTWONA=$(systemsetup -getwakeonnetworkaccess)
	#if [ ! -z "$CURRENTWONA" ]; then
	#	CURRENTWONA_ISOFF=$(echo "$CURRENTWONA" | egrep 'Off' | wc -l)
	#fi
	#
	## Will this get executed before the system sleeps?
	#if ([ $DISABLEWONA -gt 0 ] && [ $CURRENTWONA_ISOFF -gt 0 ]); then
	#	spc_disp_message "Enabling WOL via setwakeonnetworkaccess on."
	#	systemsetup -setwakeonnetworkaccess on
	#fi

	#pmset sleepnow
	shutdown -s now
	RETVAL=$?

	spc_disp_message "System shutdown returned ${RETVAL}."
	NOWTIME=$(date)
	spc_disp_message "System returned from sleep at ${NOWTIME}."

	exit $RETVAL
}

disp_help(){
	spc_disp_error_message	"Usage: ${SCRIPT} [--sleep|--safesleep|--hibernate] [--show] [--quiet] [--verbose] [--log] [--serverlog]"
	exit 1
}


####################################################################################
# main() - Process command line..
#

for ARG in $*
do
case $ARG in
	--help)
		disp_help
		;;
	--quiet)
		VERBOSE=0
		;;
	--verbose)
		VERBOSE=1
		;;
	--log)
		LOGGING=1
		spc_get_log_file
		;;
	--serverlog)
		LOGGING=1
		SERVERLOGGING=1
		spc_get_slim_server_log
		;;
	--no-wna)
		DISABLEWNA=1
		;;
	--wna)
		DISABLEWNA=0
		;;
	--womp)
		ENABLEWOMP=1
		;;
	--no-womp)
		ENABLEWOMP=0
		;;
	--show)
		JUST_SHOW=1
		;;
	--sleep|sleep|0)
		SLEEPMODE=0
		;;
	--safesleep|safesleep|3)
		SLEEPMODE=3
		;;
	# OS X refers to hibernation as 'suspend'
	--hibernate|hibernate|suspend|1|25)
		SLEEPMODE=25
		;;
	*)
		disp_help
		;;
esac
done

if [ $JUST_SHOW -gt 0 ]; then
	show_current_mode
	exit 0
fi

system_sleep $SLEEPMODE
exit $?
